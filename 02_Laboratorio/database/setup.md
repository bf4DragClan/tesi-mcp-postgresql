# Setup del laboratorio PostgreSQL con Pagila

## 1. Obiettivo del laboratorio

Il laboratorio sperimentale utilizza PostgreSQL e il database Pagila per studiare la sicurezza dell'interazione tra Large Language Models (LLM), MCP Server e database relazionali.

L'ambiente permette di analizzare:

- l'autenticazione degli MCP Server verso PostgreSQL;
- la gestione dei ruoli e dei privilegi;
- il principio del Least Privilege;
- le operazioni di lettura e scrittura;
- la separazione tra i controlli implementati dal server MCP e quelli applicati dal DBMS;
- le vulnerabilità SQL Injection;
- l'efficacia delle query parametrizzate.

Il database è eseguito localmente tramite Docker e viene utilizzato come ambiente comune per gli esperimenti sui differenti MCP Server.

## 2. Database Pagila

Il dataset utilizzato è Pagila, un database di esempio basato su uno scenario applicativo di noleggio cinematografico.

Repository ufficiale:

https://github.com/devrimgunduz/pagila

Il repository è integrato nel progetto come Git submodule:

`02_Laboratorio/pagila-source`

La revisione del submodule è registrata nel repository principale, così da mantenere identificabile la versione del dataset utilizzata.

### 2.1 Configurazione PostgreSQL

Il database viene eseguito all'interno di un container Docker tramite Docker Compose.

| Parametro | Valore |
|---|---|
| Database | `pagila` |
| Container | `tesi-pagila` |
| Immagine | `02_laboratorio-pagila` |
| Versione PostgreSQL verificata | 18.6 |
| Porta interna | 5432 |
| Porta host | 5434 |
| Host | `127.0.0.1` |
| Volume Docker | `02_laboratorio_pagila_data` |

La porta PostgreSQL è pubblicata esclusivamente sull'indirizzo di loopback `127.0.0.1`.

Il volume Docker conserva i dati anche dopo l'arresto o la ricreazione del container.

### 2.2 Struttura del dataset

Tra le principali tabelle utilizzate nel laboratorio sono presenti:

- `public.customer`
- `public.film`
- `public.actor`
- `public.inventory`
- `public.rental`
- `public.payment`

Dopo l'inizializzazione sono stati eseguiti i seguenti conteggi:

```sql
SELECT COUNT(*) AS customers FROM public.customer;
SELECT COUNT(*) AS films FROM public.film;
SELECT COUNT(*) AS rentals FROM public.rental;
SELECT COUNT(*) AS payments FROM public.payment;
SELECT COUNT(*) AS inventory FROM public.inventory;
SELECT COUNT(*) AS actors FROM public.actor;
```

Risultati ottenuti:

| Tabella | Record |
|---|---:|
| `public.customer` | 999 |
| `public.film` | 1000 |
| `public.rental` | 51805 |
| `public.payment` | 51061 |
| `public.inventory` | 4581 |
| `public.actor` | 200 |

Questi valori costituiscono il riferimento iniziale per i controlli di integrità.

## 3. Avvio dell'ambiente Docker

La configurazione Docker è contenuta nel file:

`02_Laboratorio/docker-compose.yml`

Le variabili d'ambiente sono conservate nel file locale:

`02_Laboratorio/.env.pagila`

Il file non deve essere pubblicato su GitHub.

È disponibile il modello:

`02_Laboratorio/.env.example`

Per predisporre l'ambiente su una nuova installazione, dalla directory `02_Laboratorio` eseguire:

```powershell
Copy-Item .env.example .env.pagila
```

Impostare nel file `.env.pagila` una password sicura per l'utente amministrativo PostgreSQL.

Per avviare il database:

```powershell
docker compose --env-file .env.pagila up -d --build
```

Per verificare lo stato:

```powershell
docker compose --env-file .env.pagila ps
```

Per visualizzare i log:

```powershell
docker compose --env-file .env.pagila logs -f pagila
```

Per arrestare il container preservando i dati:

```powershell
docker compose --env-file .env.pagila down
```

Gli script SQL del progetto Pagila vengono montati nella directory `/docker-entrypoint-initdb.d` del container e sono eseguiti durante l'inizializzazione del database.

La normale modifica degli script di inizializzazione non comporta una nuova importazione su un volume già inizializzato.

**Attenzione:** non utilizzare `docker compose down -v` durante il normale utilizzo del laboratorio, perché eliminerebbe anche il volume contenente i dati Pagila.

## 4. Organizzazione degli schemi

Per mantenere separati il dataset originale e i dati sperimentali, il database utilizza due schemi distinti.

### 4.1 Schema `public`

Contiene le tabelle originali del dataset Pagila.

Le tabelle originali vengono utilizzate principalmente per le operazioni di lettura e come riferimento per verificare che gli esperimenti non alterino i dati iniziali.

### 4.2 Schema `security_lab`

È stato creato uno schema separato per gli esperimenti di sicurezza.

Contiene le seguenti tabelle:

- `security_lab.test_customers`
- `security_lab.test_accounts`
- `security_lab.mcp_readonly_probe`

La tabella `mcp_readonly_probe` contiene un contatore sintetico utilizzato nei test di scrittura indiretta attraverso il tool MCP. La funzione `security_lab.readonly_write_probe()` incrementa il contatore mediante un `UPDATE` interno, se la transazione lo permette. Nei test documentati, il valore iniziale era `0` e, dopo il controllo positivo sul profilo writer, è arrivato a `1`.

La tabella `test_customers` contiene quattro clienti sintetici:

| ID | Nome | Cognome |
|---:|---|---|
| 1 | Ada | Lovelace |
| 2 | Alan | Turing |
| 3 | Grace | Hopper |
| 4 | Katherine | Johnson |

La tabella `test_accounts` contiene quattro record associati ai clienti attraverso una chiave esterna.

I dati sono artificiali e vengono utilizzati esclusivamente per gli esperimenti.

La separazione permette di effettuare test CRUD e SQL Injection senza intervenire sui dati originali di Pagila.

## 5. Ruoli PostgreSQL e principio del Least Privilege

Per verificare l'efficacia dei diversi livelli di autorizzazione sono stati creati tre ruoli PostgreSQL dedicati.

| Ruolo | Funzione |
|---|---|
| `mcp_readonly_pagila` | Accesso in sola lettura |
| `mcp_writer_pagila` | Lettura, inserimento e modifica |
| `mcp_crud_pagila` | Lettura, inserimento, modifica ed eliminazione |

I ruoli sono account di connessione distinti e non utilizzano l'utente amministrativo `postgres`.

### 5.1 Ruolo read-only

Il ruolo `mcp_readonly_pagila` dispone dei privilegi necessari per:

- connettersi al database;
- accedere allo schema `public`;
- eseguire SELECT sulle tabelle originali di Pagila;
- accedere in lettura allo schema `security_lab`;
- eseguire le due funzioni di ricerca utilizzate nell'esperimento SQL Injection.

Non dispone dei privilegi INSERT, UPDATE e DELETE sulle tabelle.

### 5.2 Ruolo writer

Il ruolo `mcp_writer_pagila` dispone dei seguenti privilegi sulle tabelle dello schema `security_lab`:

- SELECT;
- INSERT;
- UPDATE.

Non dispone dei privilegi:

- DELETE;
- TRUNCATE.

Non gli vengono assegnati privilegi di accesso alle tabelle originali dello schema `public`.

### 5.3 Ruolo CRUD

Il ruolo `mcp_crud_pagila` dispone dei seguenti privilegi sulle tabelle dello schema `security_lab`:

- SELECT;
- INSERT;
- UPDATE;
- DELETE.

Non dispone del privilegio TRUNCATE e non riceve privilegi amministrativi sul database.

### 5.4 Matrice dei privilegi

La configurazione è stata verificata tramite le funzioni PostgreSQL `has_database_privilege`, `has_schema_privilege` e `has_table_privilege`.

| Operazione | Read-only | Writer | CRUD |
|---|---|---|---|
| CONNECT | Sì | Sì | Sì |
| USAGE su `security_lab` | Sì | Sì | Sì |
| CREATE nello schema | No | No | No |
| SELECT | Sì | Sì | Sì |
| INSERT | No | Sì | Sì |
| UPDATE | No | Sì | Sì |
| DELETE | No | No | Sì |
| TRUNCATE | No | No | No |

### 5.5 Creazione e configurazione dei ruoli

Lo script:

`02_Laboratorio/database/security_lab.sql`

contiene la definizione dello schema sperimentale, delle tabelle, dei dati sintetici e dei privilegi dei tre ruoli. Comprende anche la tabella `mcp_readonly_probe`, la funzione `readonly_write_probe()` (`VOLATILE`, `SECURITY INVOKER`) e il privilegio `EXECUTE` concesso a `mcp_writer_pagila`.

**Prerequisito:** il ruolo `mcp_readonly_pagila` deve essere già presente nel database prima dell'esecuzione dello script. Lo script utilizza `IF NOT EXISTS` e `ON CONFLICT DO NOTHING` per gli oggetti e i dati di prova: rieseguirlo non azzera il contatore esistente.

Lo script deve essere eseguito con l'utente amministrativo PostgreSQL:

```powershell
docker cp ".\database\security_lab.sql" tesi-pagila:/tmp/security_lab.sql
docker exec tesi-pagila psql -U postgres -d pagila -v ON_ERROR_STOP=1 -f /tmp/security_lab.sql
```

Le password dei due ruoli aggiuntivi sono state impostate interattivamente tramite PostgreSQL:

```sql
\password mcp_writer_pagila
\password mcp_crud_pagila
```

La password del ruolo read-only è stata impostata con la stessa modalità.

Le credenziali non devono essere inserite negli script SQL o nei file versionati.

## 6. Test diretti dei privilegi PostgreSQL

I primi test sono stati eseguiti direttamente sul database, senza utilizzare gli MCP Server.

### 6.1 Test read-only

Il collegamento è stato effettuato con `mcp_readonly_pagila`.

È stata verificata la possibilità di leggere le tabelle sperimentali.

Il tentativo di INSERT è stato rifiutato da PostgreSQL con un errore di autorizzazione.

Il numero di clienti nella tabella `security_lab.test_customers` è rimasto pari a quattro.

### 6.2 Test writer

Il ruolo `mcp_writer_pagila` è stato utilizzato per verificare INSERT, UPDATE e DELETE.

Risultati:

| Operazione | Risultato |
|---|---|
| INSERT | Consentita |
| UPDATE | Consentita |
| DELETE | Rifiutata |
| Accesso a `public.customer` | Rifiutato |

Le operazioni consentite sono state eseguite all'interno di transazioni successivamente annullate con ROLLBACK.

La cancellazione è stata respinta con:

```text
ERROR: permission denied for table test_customers
```

Il test ha confermato che il ruolo può modificare esclusivamente i dati sperimentali secondo i privilegi assegnati.

### 6.3 Test CRUD

Il ruolo `mcp_crud_pagila` è stato utilizzato per verificare tutte le operazioni:

- INSERT;
- UPDATE;
- DELETE;
- SELECT.

Le operazioni sono state eseguite all'interno di una transazione.

Dopo i test è stato eseguito ROLLBACK.

Entrambe le tabelle sperimentali sono tornate a contenere quattro record.

## 7. Integrazione DBHub

DBHub è il primo MCP Server integrato nel laboratorio.

Repository:

https://github.com/bytebase/dbhub

Il server viene eseguito localmente tramite Node.js e npm utilizzando il pacchetto:

`@bytebase/dbhub`

La comunicazione con Claude Desktop utilizza il transport `stdio`.

### 7.1 Configurazioni disponibili

Sono state realizzate configurazioni separate per i differenti profili.

| Configurazione | Utente PostgreSQL | Schema di lavoro | Modalità DBHub |
|---|---|---|---|
| `dbhub-pagila.toml` | `mcp_readonly_pagila` | `public` | Read-only |
| `dbhub-writer.toml` | `mcp_writer_pagila` | `security_lab` | Scrittura |
| `dbhub-crud.toml` | `mcp_crud_pagila` | `security_lab` | Scrittura |
| `dbhub-sqli.toml` | `mcp_readonly_pagila` | `security_lab` | Custom tool di sola lettura |
| `dbhub-readonly-writer.toml` | `mcp_writer_pagila` | `security_lab` | Read-only sul tool `execute_sql` |

Le configurazioni reali contengono credenziali e sono escluse dal repository.

Sono disponibili i corrispondenti file `.toml.example` senza password reali.

### 7.2 Tool disponibili

I profili read-only, writer e CRUD utilizzano principalmente:

- `execute_sql`;
- `search_objects`.

Nel caso di `dbhub-thesis`, `execute_sql` è configurato con:

```toml
readonly = true
max_rows = 1000
```

Nel nuovo profilo `dbhub-readonly-writer`, `execute_sql` ha `readonly = true`, pur utilizzando l'utente `mcp_writer_pagila`, che possiede permessi di scrittura sulle tabelle di prova. Questo confronto isola l'efficacia della policy del tool MCP.

Nei profili writer e CRUD, il tool `execute_sql` è configurato con:

```toml
readonly = false
max_rows = 1000
```

La possibilità effettiva di eseguire una scrittura continua a dipendere dai privilegi del ruolo PostgreSQL.

Il profilo dedicato all'esperimento SQL Injection espone invece esclusivamente due custom tool:

- `search_customer_unsafe`;
- `search_customer_safe`.

Non espone un tool SQL generico `execute_sql`.

### 7.3 Versione DBHub e riproducibilità

Nella cache npm locale è stata rilevata la versione `1.7.1` di `@bytebase/dbhub`. La nuova configurazione `dbhub-readonly-writer` è stata aggiunta a Claude Desktop indicando esplicitamente `@bytebase/dbhub@1.7.1`.

**Limite della verifica:** il controllo della cache e del file di configurazione non costituisce una prova indipendente della versione del processo realmente avviato. Per la riproducibilità, è opportuno conservare anche un'evidenza della versione caricata dal server.

## 8. Integrazione con Claude Desktop

Claude Desktop viene utilizzato come client MCP per inviare richieste ai server DBHub.

La configurazione è descritta nel documento:

`02_Laboratorio/client/claude-desktop.md`

Sono state verificate cinque connessioni MCP distinte:

| Nome server | Ruolo PostgreSQL |
|---|---|
| `dbhub-thesis` | `mcp_readonly_pagila` |
| `dbhub-writer` | `mcp_writer_pagila` |
| `dbhub-crud` | `mcp_crud_pagila` |
| `dbhub-sqli` | `mcp_readonly_pagila` |
| `dbhub-readonly-writer` | `mcp_writer_pagila` |

Per ogni connessione è stata verificata l'identità dell'utente PostgreSQL tramite:

```sql
SELECT current_database(), current_user;
```

Le risposte ottenute hanno confermato il corretto utilizzo dei diversi ruoli.

## 9. Test di sicurezza tramite MCP

### 9.1 Test read-only

Attraverso `dbhub-thesis` è stata eseguita una SELECT sulla tabella originale `public.customer`.

Risultato:

`999`

È stato successivamente tentato un UPDATE:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE false;
```

DBHub ha bloccato la query prima di inviarla a PostgreSQL.

Errore restituito:

```text
code: READONLY_VIOLATION
Read-only mode is enabled.
Only the following SQL operations are allowed:
select, with, explain, show
```

Una nuova SELECT ha confermato che il numero di clienti era rimasto pari a 999.

### 9.2 Verifica indipendente PostgreSQL

Per distinguere il comportamento di DBHub da quello del database è stato effettuato un collegamento diretto con `mcp_readonly_pagila`.

Il tentativo di UPDATE sulla tabella `public.customer` è stato respinto da PostgreSQL con:

```text
ERROR: permission denied for table customer
```

La transazione è stata annullata con ROLLBACK.

Il conteggio finale è rimasto pari a 999.

### 9.3 Test Writer tramite DBHub

Attraverso `dbhub-writer` sono state verificate le operazioni sulla tabella `security_lab.test_customers`.

È stato inserito un record temporaneo con ID 9010.

L'inserimento è riuscito e il record è stato verificato tramite SELECT.

Successivamente il campo `notes` è stato aggiornato correttamente.

Il tentativo di DELETE è stato rifiutato da PostgreSQL:

```text
error: permission denied for table test_customers
code: EXECUTION_ERROR
```

Una SELECT successiva ha confermato che il record 9010 era ancora presente.

### 9.4 Test CRUD tramite DBHub

Attraverso `dbhub-crud` è stato eliminato il record temporaneo 9010.

Successivamente è stato inserito un record con ID 9020, modificato e poi eliminato.

La verifica finale ha restituito zero record con ID 9020.

Questo esperimento ha confermato che `mcp_crud_pagila` permette tutte le operazioni CRUD previste.

### 9.5 Confronto read-only e writer a parità di utente PostgreSQL

Le configurazioni `dbhub-writer` e `dbhub-readonly-writer` utilizzano entrambe il ruolo `mcp_writer_pagila`, ma differiscono nell'impostazione `readonly` di `execute_sql`.

Sul profilo `dbhub-readonly-writer`, una `SELECT` preliminare ha confermato l'assenza della riga con `customer_id = -1`. Il seguente tentativo di scrittura è stato quindi effettuato su una riga inesistente:

```sql
UPDATE security_lab.test_customers
SET notes = notes
WHERE customer_id = -1;
```

**Risultato:** `success = false`, `code = READONLY_VIOLATION`. Il controllo DBHub ha respinto la query.

È stato inoltre eseguito il tentativo di scrittura annidato:

```sql
WITH attempted_update AS (
    UPDATE security_lab.test_customers
    SET notes = notes
    WHERE customer_id = -1
    RETURNING customer_id
)
SELECT COUNT(*) FROM attempted_update;
```

**Risultato:** `READONLY_VIOLATION`. In questo caso la presenza dell'`UPDATE` nella `WITH` non ha consentito di aggirare la policy.

### 9.6 Transazioni read-only e scritture indirette tramite funzioni

Nella connessione `dbhub-readonly-writer`, l'istruzione:

```sql
SELECT current_setting('transaction_read_only') AS transaction_read_only;
```

ha restituito `on`. Per il profilo `dbhub-writer`, usando lo stesso ruolo PostgreSQL, `transaction_read_only` e `default_transaction_read_only` risultavano `off`.

Per studiare una scrittura indiretta è stata creata la funzione `security_lab.readonly_write_probe()`, che prova a incrementare `security_lab.mcp_readonly_probe.counter`. La funzione è `SECURITY INVOKER`, dunque non acquisisce privilegi superiori a quelli dell'utente chiamante.

La chiamata sperimentale è:

```sql
SELECT security_lab.readonly_write_probe();
```

| Server MCP | Contatore prima | Esito della chiamata | Contatore dopo |
|---|---:|---|---:|
| `dbhub-writer` | 0 | Successo; valore restituito `1` | 1 |
| `dbhub-readonly-writer` | 1 | `EXECUTION_ERROR`: `cannot execute UPDATE in a read-only transaction` | 1 |

Il primo risultato mostra che la funzione è realmente in grado di scrivere quando la configurazione lo consente. Nel secondo caso la `SELECT` è stata accettata come istruzione iniziale, ma PostgreSQL ha bloccato l'`UPDATE` interno per effetto della transazione read-only impostata nel percorso MCP. Il contatore è rimasto invariato.

### 9.7 SQL injection nei tool predefiniti di DBHub

È stato testato il tool `search_objects` sul profilo `dbhub-readonly-writer`, con richieste limitate ai metadati dello schema `security_lab` e senza modifiche al database.

| Parametro verificato | Ricerca normale | Input con sintassi SQL | Risultato dell'input alterato |
|---|---|---|---|
| `pattern` | `mcp_readonly_probe` → 1 tabella | `mcp_readonly_probe' OR '1'='1` | 0 oggetti |
| `schema` | `security_lab` | `security_lab' OR '1'='1` | `SCHEMA_NOT_FOUND` |
| `table` | `mcp_readonly_probe` → 2 colonne | `mcp_readonly_probe' OR '1'='1` | 0 colonne |

I test non hanno evidenziato SQL injection con questi specifici payload. Il messaggio `SCHEMA_NOT_FOUND` riportava anche l'elenco degli schemi disponibili (`public`, `security_lab`), una forma di esposizione di metadati da distinguere dalla SQL injection.

L'analisi del codice sorgente taggato `v1.7.1` mostra che, nei percorsi esaminati, `search_objects` filtra `pattern` dopo aver recuperato i nomi degli oggetti e usa verifiche/parametri per `schema` e `table`. I risultati dei test sono coerenti con questi meccanismi. Il tool `execute_sql`, invece, riceve intenzionalmente SQL dal client; ciò non costituisce di per sé una SQL injection. La sua superficie di sicurezza va valutata rispetto alle policy e ai privilegi applicati.

**Limiti:** l'assenza di SQL injection nei tre casi non dimostra che ogni parametro, variante di query o versione del server sia immune. I dettagli dei test, dei messaggi e dei riferimenti al codice sono raccolti in [`dbhub_security_tests.md`](dbhub_security_tests.md).

## 10. Esperimento SQL Injection

Per analizzare il comportamento delle query costruite con input non affidabili è stato realizzato un esperimento dedicato.

Il test utilizza due funzioni PostgreSQL:

- `security_lab.search_customer_unsafe`;
- `security_lab.search_customer_safe`.

La prima utilizza SQL dinamico con concatenazione diretta dell'input.

La seconda utilizza una query statica che tratta il parametro come dato.

Le due funzioni sono esposte tramite i custom tool DBHub:

- `search_customer_unsafe`;
- `search_customer_safe`.

Entrambi i custom tool utilizzano parametri tipizzati e sono configurati in sola lettura.

La descrizione completa dell'esperimento e dei risultati è disponibile in:

`02_Laboratorio/database/sql_injection_lab.md`

### 10.1 Risultati sintetici

È stato utilizzato il payload:

```text
x' OR '1'='1
```

Con la funzione vulnerabile sono stati restituiti tutti e quattro i record della tabella sperimentale.

Con la funzione parametrizzata non è stato restituito alcun record.

È stata inoltre verificata una SQL Injection basata su UNION, attraverso la quale sono state recuperate informazioni sul database e sull'identità della connessione.

I risultati dimostrano che la modalità read-only non elimina automaticamente i rischi di esposizione dei dati derivanti da una query vulnerabile.

## 11. Risultati complessivi

Il laboratorio ha permesso di verificare sperimentalmente:

- tre profili di autorizzazione PostgreSQL, utilizzati attraverso cinque configurazioni MCP distinte;
- l'efficacia del controllo read-only di DBHub contro un `UPDATE` diretto e contro una scrittura annidata in `WITH`;
- l'applicazione di transazioni read-only da parte della configurazione MCP, con blocco di una modifica tentata da una funzione richiamata mediante `SELECT`;
- il blocco delle operazioni non autorizzate da parte dei privilegi PostgreSQL;
- l'esecuzione delle operazioni CRUD tramite i profili appropriati;
- la vulnerabilità SQL injection del custom tool sperimentale basato su una funzione SQL dinamica e la protezione offerta dalla funzione statica;
- l'assenza di SQL injection osservata nei test mirati sui parametri `pattern`, `schema` e `table` di `search_objects`.

I risultati costituiscono la baseline sperimentale del progetto e saranno utilizzati per il confronto tra le differenti implementazioni MCP Server analizzate nella fase di ricerca.

## 12. Documentazione correlata e prossimi controlli

- [`sql_injection_lab.md`](sql_injection_lab.md): esperimenti sui custom tool sicuro e vulnerabile.
- [`dbhub_security_tests.md`](dbhub_security_tests.md): resoconto dettagliato delle verifiche read-only e dei tool predefiniti DBHub, incluso l'approfondimento sulla vulnerabilità storica CVE-2026-61788.
- [`security_lab.sql`](security_lab.sql): schema sperimentale, privilegi e funzione di prova riproducibili.
- `02_Laboratorio/client/claude-desktop.md`: documentazione del client e delle configurazioni MCP.

Per consolidare la riproducibilità, restano utili una verifica indipendente della versione DBHub effettivamente avviata da Claude Desktop e la conservazione delle risposte JSON integrali dei tool, senza credenziali. Le conclusioni sono circoscritte agli esperimenti realmente eseguiti nel laboratorio locale.
