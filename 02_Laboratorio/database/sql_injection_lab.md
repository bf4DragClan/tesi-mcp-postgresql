# Esperimento SQL Injection nell'interazione tra LLM, MCP Server e PostgreSQL

## 1. Obiettivo

Questo esperimento analizza il rischio di SQL Injection nell'interazione tra un agente AI, un MCP Server e un database PostgreSQL.

L'obiettivo è confrontare due implementazioni di una stessa funzionalità di ricerca clienti:

- una funzione vulnerabile, che costruisce dinamicamente la query SQL concatenando direttamente l'input;
- una funzione protetta, che utilizza una query statica e tratta l'input come parametro.

Il test viene eseguito attraverso DBHub e Claude Desktop, utilizzando custom tool MCP dedicati.

L'esperimento permette di verificare se un input appositamente costruito possa modificare la logica della query e ottenere dati differenti rispetto a quelli previsti dalla ricerca originale.

## 2. Ambiente sperimentale

Il test utilizza il database Pagila già configurato nel laboratorio.

| Parametro | Valore |
|---|---|
| DBMS | PostgreSQL |
| Versione verificata | 18.6 |
| Database | `pagila` |
| Schema | `security_lab` |
| Tabella | `test_customers` |
| Record iniziali | 4 |
| MCP Server | DBHub |
| Client | Claude Desktop |
| Ruolo PostgreSQL | `mcp_readonly_pagila` |

La connessione utilizzata è:

`dbhub-sqli`

Il ruolo PostgreSQL dispone di privilegi di lettura sulle tabelle sperimentali e non dispone dei privilegi di scrittura.

## 3. Struttura delle funzioni

Sono state realizzate due funzioni PostgreSQL con lo stesso obiettivo: cercare un cliente utilizzando il cognome ricevuto come parametro.

### 3.1 Funzione vulnerabile: search_customer_unsafe

La funzione vulnerabile costruisce una query SQL dinamica concatenando direttamente il valore ricevuto.

Implementazione:

```sql
CREATE OR REPLACE FUNCTION security_lab.search_customer_unsafe(
    p_last_name TEXT
)
RETURNS TABLE (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(150)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN

    RETURN QUERY EXECUTE
        'SELECT c.customer_id, c.first_name, c.last_name, c.email ' ||
        'FROM security_lab.test_customers AS c ' ||
        'WHERE c.last_name = ''' || p_last_name || '''';

END;
$function$;
```

Il problema si trova nell'espressione:

```sql
''' || p_last_name || '''
```

Il parametro viene inserito direttamente nella stringa SQL che sarà eseguita dal database.

Di conseguenza, un input contenente caratteri e operatori SQL può alterare la struttura della query.

### 3.2 Funzione protetta: search_customer_safe

La seconda funzione utilizza una query statica.

Implementazione:

```sql
CREATE OR REPLACE FUNCTION security_lab.search_customer_safe(
    p_last_name TEXT
)
RETURNS TABLE (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(150)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN

    RETURN QUERY
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email
    FROM security_lab.test_customers AS c
    WHERE c.last_name = p_last_name;

END;
$function$;
```

In questo caso il valore ricevuto viene utilizzato come dato e non viene concatenato a una stringa SQL dinamica.

La struttura della query rimane invariata indipendentemente dal contenuto dell'input.

## 4. Configurazione dei privilegi

Entrambe le funzioni utilizzano la modalità:

`SECURITY INVOKER`

Le istruzioni vengono pertanto eseguite con i privilegi dell'utente che invoca la funzione.

L'accesso in esecuzione alle funzioni è stato limitato al ruolo sperimentale read-only:

```sql
REVOKE ALL ON FUNCTION
    security_lab.search_customer_unsafe(TEXT)
FROM PUBLIC, mcp_readonly_pagila,
     mcp_writer_pagila, mcp_crud_pagila;

REVOKE ALL ON FUNCTION
    security_lab.search_customer_safe(TEXT)
FROM PUBLIC, mcp_readonly_pagila,
     mcp_writer_pagila, mcp_crud_pagila;

GRANT EXECUTE ON FUNCTION
    security_lab.search_customer_unsafe(TEXT)
TO mcp_readonly_pagila;

GRANT EXECUTE ON FUNCTION
    security_lab.search_customer_safe(TEXT)
TO mcp_readonly_pagila;
```

La configurazione mantiene l'esperimento separato dalle connessioni writer e CRUD.

Il ruolo read-only può eseguire le funzioni, ma non può modificare i dati delle tabelle.

## 5. Integrazione tramite DBHub

Per esporre le funzioni attraverso MCP è stato creato un server DBHub dedicato:

`dbhub-sqli`

La configurazione locale è:

`02_Laboratorio/dbhub/dbhub-sqli.toml`

Il server utilizza:

- database `pagila`;
- utente `mcp_readonly_pagila`;
- schema di lavoro `security_lab`;
- transport `stdio`;
- modalità read-only;
- due custom tool dedicati.

Non viene esposto il tool SQL generico `execute_sql`.

### 5.1 Custom tool vulnerabile

Il tool:

`search_customer_unsafe`

utilizza la seguente istruzione SQL:

```sql
SELECT *
FROM security_lab.search_customer_unsafe($1);
```

Il parametro `$1` è dichiarato come stringa attraverso la configurazione DBHub.

### 5.2 Custom tool protetto

Il tool:

`search_customer_safe`

utilizza:

```sql
SELECT *
FROM security_lab.search_customer_safe($1);
```

Anche in questo caso il parametro `$1` è dichiarato come stringa.

### 5.3 Distinzione tra parametrizzazione MCP e SQL dinamico

Un elemento importante dell'esperimento è che entrambi i custom tool DBHub utilizzano correttamente un parametro SQL.

Tuttavia, la funzione vulnerabile concatena successivamente il contenuto del parametro in una nuova query SQL dinamica.

La parametrizzazione della query esterna, quindi, non corregge automaticamente la vulnerabilità presente nella query interna.

Questa distinzione permette di analizzare la sicurezza dell'intera catena di esecuzione SQL e non soltanto del livello MCP.

## 6. Test 1 – Ricerca normale

Il primo test utilizza un input legittimo:

```text
Lovelace
```

Il parametro viene passato al custom tool `search_customer_unsafe`.

Risultato:

| customer_id | first_name | last_name | email |
|---:|---|---|---|
| 1 | Ada | Lovelace | ada.lovelace@example.test |

Numero di record restituiti:

`1`

Il risultato è coerente con il comportamento atteso della funzione di ricerca.

## 7. Test 2 – SQL Injection classica

Il secondo test utilizza il seguente input:

```text
x' OR '1'='1
```

Il valore viene passato senza modifiche al parametro `last_name` del custom tool `search_customer_unsafe`.

La concatenazione dell'input nella query dinamica consente di alterare la condizione WHERE.

Risultato:

| customer_id | first_name | last_name | email |
|---:|---|---|---|
| 1 | Ada | Lovelace | ada.lovelace@example.test |
| 2 | Alan | Turing | alan.turing@example.test |
| 3 | Grace | Hopper | grace.hopper@example.test |
| 4 | Katherine | Johnson | katherine.johnson@example.test |

Numero di record restituiti:

`4`

La funzione ha restituito tutti i record presenti nella tabella sperimentale invece di filtrare i risultati in base al cognome.

Il test conferma che la funzione `search_customer_unsafe` è vulnerabile a SQL Injection.

## 8. Test 3 – Verifica della funzione parametrizzata

Lo stesso input:

```text
x' OR '1'='1
```

è stato passato al custom tool `search_customer_safe`.

Risultato:

`0 record`

La funzione ha interpretato l'intero contenuto del parametro come un valore letterale.

Non essendoci un cliente con quel cognome esatto, la query non ha restituito risultati.

Il confronto dimostra l'efficacia della query statica parametrizzata nel prevenire la modifica della struttura SQL attraverso il valore dell'input.

## 9. Test 4 – UNION-based SQL Injection

È stato effettuato un ulteriore test attraverso il custom tool vulnerabile.

L'obiettivo era verificare se fosse possibile utilizzare una UNION per ottenere informazioni ulteriori rispetto ai record normalmente restituiti dalla ricerca clienti.

Durante il test è stato individuato il numero di colonne della query originale:

`4`

La verifica ha consentito di recuperare le seguenti informazioni:

| Informazione | Risultato |
|---|---|
| Database corrente | `pagila` |
| Utente PostgreSQL | `mcp_readonly_pagila` |
| Versione PostgreSQL | `18.6` |

Il test dimostra che la vulnerabilità non permette soltanto di alterare il filtro della ricerca, ma può anche essere sfruttata per ottenere informazioni sul database.

Il payload UNION esatto non è stato conservato nel resoconto dell'esperimento. Non viene quindi ricostruito in questa documentazione.

## 10. Confronto dei risultati

| Test | Funzione unsafe | Funzione safe |
|---|---|---|
| Ricerca `Lovelace` | 1 record | 1 record previsto |
| Input `x' OR '1'='1` | 4 record | 0 record |
| Modifica della logica SQL | Possibile | Non ottenuta |
| Esposizione tramite UNION | Verificata | Non verificata come possibile |

Il confronto mostra che le due funzioni, pur ricevendo lo stesso parametro ed essendo esposte attraverso lo stesso server MCP, hanno comportamenti differenti.

## 11. Interpretazione dal punto di vista della sicurezza

L'esperimento permette di evidenziare alcuni aspetti.

### 11.1 Modalità read-only e SQL Injection

La modalità read-only di DBHub limita le operazioni SQL ammesse dal tool, ma non impedisce necessariamente che una SELECT costruita in modo vulnerabile restituisca un insieme di dati più ampio rispetto a quello previsto.

Un utente privo dei privilegi di scrittura può comunque essere coinvolto in un problema di riservatezza dei dati.

### 11.2 Privilegi PostgreSQL e impatto della vulnerabilità

L'utilizzo di `mcp_readonly_pagila` limita le operazioni che possono essere eseguite direttamente sulle tabelle.

Il ruolo utilizzato nell'esperimento non dispone dei privilegi di INSERT, UPDATE e DELETE.

La vulnerabilità osservata riguarda quindi la manipolazione della query di lettura e l'esposizione di informazioni, non un'escalation di privilegi o la modifica dei dati.

### 11.3 Parametrizzazione

La funzione protetta utilizza una query statica, separando la struttura SQL dai valori ricevuti.

Questa soluzione impedisce che il contenuto del parametro venga interpretato come parte della sintassi SQL.

Il confronto sottolinea l'importanza di applicare la parametrizzazione in ogni punto in cui vengono costruite query dinamiche, comprese le funzioni e le procedure richiamate da un MCP Server.

## 12. Limiti dell'esperimento

L'esperimento utilizza un dataset sintetico e un ambiente locale controllato.

I risultati dimostrano il comportamento delle due funzioni realizzate, ma non possono essere automaticamente generalizzati a tutti gli MCP Server o a tutte le applicazioni basate su LLM.

Il test UNION ha confermato l'esposizione di alcune informazioni sull'istanza PostgreSQL, ma il payload esatto non è stato conservato nel resoconto.

Non è stata dimostrata la possibilità di scrivere, cancellare dati o ottenere privilegi superiori attraverso questa vulnerabilità.

Ulteriori esperimenti potranno analizzare l'efficacia delle stesse contromisure in altri MCP Server e con differenti modalità di esposizione dei tool.

## 13. Conclusioni

L'esperimento ha dimostrato che una funzione PostgreSQL che concatena input non affidabili in una query SQL dinamica può essere vulnerabile a SQL Injection anche quando viene richiamata attraverso un custom tool MCP che utilizza un parametro tipizzato.

La funzione vulnerabile ha restituito tutti i record della tabella sperimentale utilizzando un input costruito appositamente e ha consentito un ulteriore test di tipo UNION.

La funzione parametrizzata ha invece trattato lo stesso input come valore letterale, restituendo zero risultati.

Il risultato evidenzia che la sicurezza di un sistema basato su LLM, MCP Server e database non dipende esclusivamente dai privilegi dell'utente o dai controlli del server MCP, ma anche dalla correttezza delle query e delle funzioni eseguite a livello di database.