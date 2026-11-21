# Verifica dei controlli di sicurezza di DBHub

## 1. Obiettivo

Questo documento raccoglie gli esperimenti svolti per valutare i controlli di sicurezza del server MCP **DBHub** nell'accesso al database PostgreSQL **Pagila**. L'approfondimento nasce da due domande:

1. La modalità `readonly = true` di DBHub impedisce modifiche ai dati anche quando l'utente PostgreSQL dispone di privilegi di scrittura, e anche quando una modifica è nascosta in una query apparentemente di lettura?
2. I tool predefiniti `search_objects` ed `execute_sql` presentano superfici di SQL injection, e come vengono trattati gli input ricevuti?

Gli esperimenti sono eseguiti tramite **Claude Desktop**, usando esclusivamente i server e i tool indicati in ciascun test. Il dataset originale nello schema `public` non è stato modificato: le verifiche potenzialmente mutative si sono concentrate sullo schema di laboratorio `security_lab`.

Questo documento integra, senza sostituirli, `setup.md` e `sql_injection_lab.md`.

## 2. Ambiente e configurazioni

| Componente | Valore |
|---|---|
| DBMS | PostgreSQL 18.6 |
| Database | `pagila` |
| Container Docker | `tesi-pagila` |
| Connessione host | `127.0.0.1:5434` |
| Schema sperimentale | `security_lab` |
| Client MCP | Claude Desktop |
| MCP Server | DBHub (`@bytebase/dbhub`) |
| Versione DBHub individuata nella cache npm | `1.7.1` |
| Versione fissata nella configurazione Claude del nuovo profilo | `@bytebase/dbhub@1.7.1` |

**Nota di riproducibilità:** il ritrovamento della versione 1.7.1 nella cache npm e l'impostazione del pacchetto nella configurazione Claude non equivalgono, da soli, a una registrazione indipendente della versione del processo effettivamente avviato. Prima di presentare risultati come specifici della versione, è opportuno conservare anche un'evidenza dell'avvio del server.

### 2.1 Confronto dei profili MCP

| Server MCP | Ruolo PostgreSQL | `execute_sql.readonly` | Finalità |
|---|---|---|---|
| `dbhub-thesis` | `mcp_readonly_pagila` | `true` | Lettura protetta su entrambi i livelli |
| `dbhub-writer` | `mcp_writer_pagila` | `false` | Controllo positivo delle operazioni di scrittura |
| `dbhub-crud` | `mcp_crud_pagila` | `false` | Verifica dei privilegi CRUD |
| `dbhub-sqli` | `mcp_readonly_pagila` | Non espone `execute_sql` generico | Custom tool sicuro e vulnerabile |
| **`dbhub-readonly-writer`** | **`mcp_writer_pagila`** | **`true`** | **Isolare l'effetto del controllo MCP** |

Il profilo `dbhub-readonly-writer` riutilizza **lo stesso account PostgreSQL** del profilo `dbhub-writer`. Il ruolo `mcp_writer_pagila` possiede privilegi di lettura e modifica sui dati sperimentali; nei due profili cambia la policy del tool MCP, non l'identità PostgreSQL.

Il file locale `dbhub/dbhub-readonly-writer.toml` contiene le credenziali ed è escluso da Git. Il file `dbhub/dbhub-readonly-writer.toml.example` contiene soltanto segnaposto ed è versionabile.

## 3. Verifica del blocco delle scritture dirette

### Test 1 — Identità della connessione

**Server:** `dbhub-readonly-writer` — **Tool:** `execute_sql`.

```sql
SELECT current_database(), current_user;
```

Risultato osservato: `pagila`, `mcp_writer_pagila`. La connessione è funzionante e utilizza il ruolo PostgreSQL previsto.

### Test 2 — `UPDATE` diretto

La lettura preliminare conferma l'assenza della riga scelta:

```sql
SELECT COUNT(*)
FROM security_lab.test_customers
WHERE customer_id = -1;
```

**Risultato:** `count = 0`.

Tentativo di scrittura:

```sql
UPDATE security_lab.test_customers
SET notes = notes
WHERE customer_id = -1;
```

**Risultato osservato:**

```text
success: false
code: READONLY_VIOLATION
error: Read-only mode is enabled. Only the following SQL operations are allowed: select, with, explain, show
```

**Interpretazione:** DBHub ha rifiutato l'istruzione di modifica prima che potesse avere effetti sul database. L'uso di una riga inesistente evita alterazioni dei dati anche in presenza di comportamenti inattesi. Questo test dimostra il blocco di un `UPDATE` diretto, non ancora la robustezza rispetto a scritture indirette.

### Test 3 — `WITH` contenente un `UPDATE`

```sql
WITH attempted_update AS (
    UPDATE security_lab.test_customers
    SET notes = notes
    WHERE customer_id = -1
    RETURNING customer_id
)
SELECT COUNT(*) FROM attempted_update;
```

**Risultato osservato:**

```text
success: false
code: READONLY_VIOLATION
error: Read-only mode is enabled. Only the following SQL operations are allowed: select, with, explain, show
```

**Interpretazione:** in questa prova il controllo non si è limitato ad autorizzare la query in quanto iniziava con `WITH`: ha rifiutato la presenza dell'operazione di scrittura. Il solo codice d'errore non permette di identificare con certezza l'algoritmo di classificazione utilizzato.

## 4. Verifica della transazione read-only

### Test 4 — Profilo `dbhub-readonly-writer`

```sql
SELECT current_setting('transaction_read_only') AS transaction_read_only;
```

**Risultato osservato:** `on`.

Il valore descrive la **transazione in cui è eseguita la query**, non dimostra che tutte le sessioni PostgreSQL siano globalmente in sola lettura.

### Test 5 — Profilo `dbhub-writer`

```sql
SELECT
    current_database(),
    current_user,
    current_setting('transaction_read_only') AS transaction_read_only,
    current_setting('default_transaction_read_only') AS default_transaction_read_only;
```

**Risultato osservato:**

| Campo | Valore |
|---|---|
| `current_database` | `pagila` |
| `current_user` | `mcp_writer_pagila` |
| `transaction_read_only` | `off` |
| `default_transaction_read_only` | `off` |

**Interpretazione del confronto:** a parità di utente PostgreSQL, il profilo MCP con `readonly = true` ha eseguito la `SELECT` in una transazione read-only, mentre il profilo con `readonly = false` l'ha eseguita in una transazione non read-only.

## 5. Scritture indirette attraverso una funzione PostgreSQL

### 5.1 Preparazione della prova

È stata creata la tabella sperimentale:

```sql
CREATE TABLE IF NOT EXISTS security_lab.mcp_readonly_probe (
    id integer PRIMARY KEY,
    counter integer NOT NULL DEFAULT 0
);

INSERT INTO security_lab.mcp_readonly_probe (id, counter)
VALUES (1, 0)
ON CONFLICT (id) DO NOTHING;
```

La funzione di prova, definita `SECURITY INVOKER`, tenta di aggiornare la tabella:

```sql
CREATE OR REPLACE FUNCTION security_lab.readonly_write_probe()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $function$
DECLARE
    new_value integer;
BEGIN
    UPDATE security_lab.mcp_readonly_probe
    SET counter = counter + 1
    WHERE id = 1
    RETURNING counter INTO new_value;

    RETURN new_value;
END;
$function$;
```

L'esecuzione è stata concessa al ruolo `mcp_writer_pagila`, insieme ai privilegi `SELECT` e `UPDATE` sulla tabella di prova. La funzione non impiega `SECURITY DEFINER` e non eleva i privilegi del chiamante.

### Test 6 — Funzione su `dbhub-writer` (controllo positivo)

Sono state eseguite, separatamente, le seguenti query:

```sql
SELECT id, counter FROM security_lab.mcp_readonly_probe WHERE id = 1;
SELECT security_lab.readonly_write_probe();
SELECT id, counter FROM security_lab.mcp_readonly_probe WHERE id = 1;
```

**Risultati osservati:** contatore iniziale `0`, valore restituito dalla funzione `1`, contatore finale `1`.

**Interpretazione:** la funzione effettua realmente una scrittura tramite una chiamata SQL che inizia con `SELECT`, quando il tool MCP e il database consentono la modifica. Non si tratta di un aggiramento: su questo profilo `readonly = false`.

### Test 7 — Stessa funzione su `dbhub-readonly-writer`

Sono state ripetute le medesime tre query con lo stesso ruolo PostgreSQL ma con `readonly = true` sul tool MCP.

**Risultati osservati:**

| Passaggio | Risultato |
|---|---|
| Lettura iniziale | `counter = 1` |
| `SELECT security_lab.readonly_write_probe();` | `EXECUTION_ERROR` |
| Messaggio di errore | `cannot execute UPDATE in a read-only transaction` |
| Lettura finale | `counter = 1` |

**Interpretazione:** la chiamata `SELECT` non è stata respinta con `READONLY_VIOLATION`, ma l'`UPDATE` eseguito all'interno della funzione è stato vietato dalla transazione read-only PostgreSQL. Il contatore è rimasto invariato. Il confronto dimostra una difesa a due livelli nella configurazione esaminata: controllo preventivo sulle istruzioni e protezione del motore DBMS tramite transazione.

## 6. SQL injection nel tool predefinito `search_objects`

### Test 8 — Parametro `pattern`

**Server:** `dbhub-readonly-writer` — **Tool:** `search_objects`.

Parametri comuni: `object_type = "table"`, `schema = "security_lab"`, `detail_level = "names"`, `limit = 20`.

| Valore di `pattern` | `count` | Risultato |
|---|---:|---|
| `mcp_readonly_probe` | 1 | Tabella `mcp_readonly_probe` |
| `mcp_readonly_probe' OR '1'='1` | 0 | Nessun oggetto |

La stringa contenente sintassi SQL non ha allargato il risultato della ricerca.

### Test 9 — Parametro `schema`

Parametri della chiamata:

```json
{
  "object_type": "table",
  "schema": "security_lab' OR '1'='1",
  "pattern": "mcp_readonly_probe",
  "detail_level": "names",
  "limit": 20
}
```

**Risposta osservata:**

```text
success: false
code: SCHEMA_NOT_FOUND
error: Schema 'security_lab' OR '1'='1' does not exist. Available schemas: public, security_lab
```

Il valore è stato trattato come nome letterale di uno schema inesistente. La risposta include l'elenco degli schemi disponibili: si tratta di un'esposizione di metadati, distinta dalla SQL injection e da valutare in relazione al modello di autorizzazione del servizio.

### Test 10 — Parametro `table`

Parametri comuni: `object_type = "column"`, `schema = "security_lab"`, `pattern = "%"`, `detail_level = "names"`, `limit = 20`.

| Valore di `table` | `count` | Risultato |
|---|---:|---|
| `mcp_readonly_probe` | 2 | Colonne `id`, `counter` |
| `mcp_readonly_probe' OR '1'='1` | 0 | Nessuna colonna |

Non sono stati osservati errori SQL né ampliamenti anomali dei risultati.

### 6.1 Interpretazione complessiva

I test sui parametri `pattern`, `schema` e `table` non hanno evidenziato SQL injection con i payload utilizzati. Il risultato è circoscritto a queste specifiche chiamate e **non** costituisce una dimostrazione di assenza di vulnerabilità per ogni parametro, variante o futura versione del tool.

## 7. Riscontro nel codice di DBHub 1.7.1

L'esame della versione **taggata `v1.7.1`** nel repository ufficiale aggiunge elementi esplicativi alle osservazioni:

- **`search_objects` — `pattern`:** il percorso di ricerca delle tabelle recupera i nomi tramite `connector.getTables(schemaName)` e applica un filtro JavaScript dopo aver convertito il pattern LIKE in espressione regolare (`likePatternToRegex`). Il pattern non viene incorporato come frammento di SQL nel percorso esaminato.
- **`search_objects` — `schema`:** il tool verifica l'appartenenza del nome richiesto all'elenco restituito dal connettore, tramite `schemas.includes(schema)`.
- **`search_objects` — `table`:** nella ricerca delle colonne, `getTableSchema` impiega query PostgreSQL parametrizzate con `$1` e `$2` per schema e tabella.
- **`execute_sql`:** accetta intenzionalmente testo SQL dal client MCP, lo sottopone alle policy configurate e lo esegue tramite il connettore. Passare una query completa a questo tool non è, di per sé, una SQL injection; occorre distinguere la funzionalità prevista dalla manipolazione imprevista di query costruite con input non fidati.
- **Transazione read-only:** nel connettore PostgreSQL di questa versione, per `options.readonly` viene avviata una transazione con `BEGIN READ ONLY`. Ciò è coerente con il messaggio PostgreSQL rilevato nel test della funzione con effetto collaterale.

I riferimenti al codice sono elencati in fondo al documento. L'analisi statica non sostituisce la verifica del pacchetto effettivamente eseguito nel laboratorio.

## 8. Vulnerabilità storica del read-only

L'advisory ufficiale **GHSA-mwwr-p57h-56pf / CVE-2026-61788**, pubblicato il **24 giugno 2026**, descrive un aggiramento dei controlli read-only nelle versioni di `@bytebase/dbhub` **precedenti alla 0.22.6**. Il problema includeva query `SELECT` con effetti collaterali che potevano superare un controllo basato sulla classificazione SQL senza che venisse effettivamente attivata una protezione read-only a livello di database.

La **0.22.6** è la prima versione indicata come corretta. La versione **1.7.1** identificata e configurata nel nostro laboratorio è successiva a tale correzione; i test svolti sono coerenti con l'applicazione della protezione transazionale. **Non è stato eseguito un confronto sperimentale con una versione vulnerabile precedente alla 0.22.6.**

## 9. Conclusioni e limiti

I test mostrano, nel contesto del laboratorio:

1. Il profilo `dbhub-readonly-writer` respinge una scrittura diretta e una scrittura annidata in una `WITH`, pur utilizzando un ruolo PostgreSQL abilitato alle modifiche.
2. Una funzione `SECURITY INVOKER` con effetto collaterale modifica i dati su `dbhub-writer` ma non su `dbhub-readonly-writer`; nel secondo caso PostgreSQL blocca l'operazione per via della transazione read-only.
3. I payload SQL injection utilizzati sui parametri `pattern`, `schema` e `table` del tool `search_objects` non alterano le ricerche, in accordo con i percorsi di codice analizzati.
4. `execute_sql` è un tool di esecuzione SQL intenzionale: la sua sicurezza va valutata in termini di autorizzazioni, costruzione delle query e protezioni applicate, non equiparando l'input SQL esplicito a un'iniezione.

**Limiti principali:** test locali e mirati; nessun fuzzing sistematico; nessuna dimostrazione di impossibilità generale di bypass; nessuna replica su vecchie versioni vulnerabili; nessuna verifica esaustiva dei tool aggiuntivi o di altri connettori DBHub. Le risposte dei tool sono state raccolte tramite Claude Desktop e riportate nel resoconto dell'esperimento.

Gli esperimenti con i custom tool `search_customer_safe` e `search_customer_unsafe` sono documentati separatamente in `sql_injection_lab.md`. Essi mostrano che un input parametrizzato nell'interfaccia MCP può restare pericoloso se una funzione PostgreSQL interna lo concatena a una query dinamica.

## 10. Riproducibilità e documentazione

La definizione della tabella `mcp_readonly_probe`, della funzione `readonly_write_probe()` e dei relativi privilegi è stata aggiunta allo script versionabile `security_lab.sql`, senza credenziali. Lo script è stato rieseguito sul container `tesi-pagila` con `ON_ERROR_STOP=1`: esecuzione terminata con `COMMIT` e successiva verifica del contatore pari a `1`, quindi senza perdita dello stato sperimentale.

Il file `dbhub-readonly-writer.toml.example` contiene la quinta configurazione MCP con utente `mcp_writer_pagila` e `readonly = true`, ma non include password reali. La configurazione locale con segreti resta esclusa dal repository.

Il documento generale `setup.md` è stato aggiornato per includere la nuova configurazione e il riepilogo delle prove. Rimangono utili le seguenti attività di completamento:

- Controllare e aggiornare `client/claude-desktop.md` e il `README.md` generale con la quinta configurazione e il collegamento a questo resoconto.
- Conservare, se possibile, un'evidenza della versione DBHub effettivamente avviata da Claude Desktop e i log/JSON integrali dei test, senza pubblicare segreti.
- Pubblicare su GitHub le modifiche documentali dopo revisione del diff.

## 11. Riferimenti

- DBHub, sorgente `search_objects` v1.7.1: https://github.com/bytebase/dbhub/blob/v1.7.1/src/tools/search-objects.ts
- DBHub, sorgente `execute_sql` v1.7.1: https://github.com/bytebase/dbhub/blob/v1.7.1/src/tools/execute-sql.ts
- DBHub, connettore PostgreSQL v1.7.1: https://github.com/bytebase/dbhub/blob/v1.7.1/src/connectors/postgres/index.ts
- DBHub, advisory GHSA-mwwr-p57h-56pf / CVE-2026-61788: https://github.com/bytebase/dbhub/security/advisories/GHSA-mwwr-p57h-56pf
- Documentazione interna: `setup.md`; `sql_injection_lab.md`; `security_lab.sql`.
