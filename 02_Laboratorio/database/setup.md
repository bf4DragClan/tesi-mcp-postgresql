# Setup del laboratorio PostgreSQL con Pagila

## 1. Obiettivo

Il laboratorio sperimentale utilizza il database Pagila, un database di esempio basato su uno scenario applicativo di noleggio cinematografico, eseguito tramite PostgreSQL all'interno di un container Docker.

L'obiettivo è realizzare un ambiente riproducibile per studiare la sicurezza dell'interazione tra Large Language Models (LLM), MCP Server e database relazionali.

In particolare, il laboratorio permette di analizzare:

- i privilegi assegnati agli utenti PostgreSQL;
- le modalità di accesso in sola lettura;
- i controlli implementati a livello MCP Server;
- la separazione tra le responsabilità del server MCP e quelle del database;
- l'efficacia di più livelli di protezione applicati congiuntamente.

## 2. Database Pagila

Il dataset utilizzato è Pagila, disponibile nel repository:

https://github.com/devrimgunduz/pagila

Il repository è integrato nel progetto come Git submodule nella directory:

`02_Laboratorio/pagila-source`

La revisione del submodule è registrata nel repository principale, in modo da mantenere identificabile la versione utilizzata negli esperimenti.

### 2.1 Configurazione PostgreSQL

Il database è eseguito tramite Docker Compose.

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

La porta è associata all'indirizzo di loopback `127.0.0.1`, in modo da limitare l'accessibilità del servizio alla macchina locale.

### 2.2 Struttura dei dati

Pagila contiene diverse tabelle che rappresentano le entità di un sistema di noleggio cinematografico.

Tra le principali tabelle utilizzate negli esperimenti:

- `customer`
- `film`
- `actor`
- `inventory`
- `rental`
- `payment`

Il database è stato inizializzato utilizzando gli script SQL forniti dal repository Pagila, montati nella directory `/docker-entrypoint-initdb.d` del container.

### 2.3 Verifica iniziale del dataset

Dopo l'inizializzazione del database sono stati eseguiti alcuni conteggi per verificare la corretta importazione dei dati.

Query utilizzate:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;

SELECT COUNT(*) AS films
FROM public.film;

SELECT COUNT(*) AS rentals
FROM public.rental;

SELECT COUNT(*) AS payments
FROM public.payment;

SELECT COUNT(*) AS inventory
FROM public.inventory;

SELECT COUNT(*) AS actors
FROM public.actor;
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

Questi valori costituiscono il riferimento iniziale per i controlli di integrità dei dati.

## 3. Avvio dell'ambiente Docker

La configurazione Docker è contenuta nel file:

`02_Laboratorio/docker-compose.yml`

Il progetto utilizza un file locale `.env.pagila` per conservare la password amministrativa PostgreSQL.

Il file `.env.pagila` non deve essere pubblicato su GitHub.

È disponibile un file di esempio:

`02_Laboratorio/.env.example`

Per predisporre l'ambiente su una nuova installazione, copiare il file di esempio con il nome `.env.pagila` e inserire una password sicura.

Da PowerShell, nella directory `02_Laboratorio`, è possibile avviare l'ambiente con:

```powershell
Copy-Item .env.example .env.pagila

notepad .env.pagila

docker compose --env-file .env.pagila up -d --build
```

Il comando avvia il container Pagila e costruisce l'immagine a partire dal repository integrato come submodule.

Per verificare lo stato del container:

```powershell
docker compose --env-file .env.pagila ps
```

Per visualizzare i log:

```powershell
docker compose --env-file .env.pagila logs -f pagila
```

Per arrestare l'ambiente senza eliminare i dati persistenti:

```powershell
docker compose --env-file .env.pagila down
```

Il volume `pagila_data` conserva i dati PostgreSQL tra un arresto e il successivo avvio.

**Attenzione:** gli script presenti in `/docker-entrypoint-initdb.d` vengono eseguiti durante l'inizializzazione di un volume PostgreSQL vuoto. Modificarli successivamente non comporta automaticamente una nuova importazione dei dati. Non utilizzare `docker compose down -v` durante il normale utilizzo del laboratorio, perché eliminerebbe anche il volume contenente il database.

## 4. Configurazione dei ruoli PostgreSQL

Per gli esperimenti è stato creato un utente dedicato all'accesso in sola lettura:

`mcp_readonly_pagila`

Il principio adottato è quello del *Least Privilege*: l'utente utilizzato dall'MCP Server deve disporre esclusivamente dei privilegi necessari all'esecuzione delle operazioni previste.

### 4.1 Creazione del ruolo

Per accedere al database tramite l'utente amministrativo:

```powershell
docker exec -it tesi-pagila psql -U postgres -d pagila
```

Creazione del ruolo:

```sql
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'mcp_readonly_pagila'
    ) THEN
        CREATE ROLE mcp_readonly_pagila LOGIN;
    END IF;
END
$$;
```

Impostazione della password:

```sql
\password mcp_readonly_pagila
```

La password viene inserita direttamente nel prompt interattivo di PostgreSQL e non deve essere riportata nei file versionati.

### 4.2 Assegnazione dei privilegi

Sono stati assegnati i seguenti privilegi:

```sql
GRANT CONNECT ON DATABASE pagila
TO mcp_readonly_pagila;

GRANT USAGE ON SCHEMA public
TO mcp_readonly_pagila;

GRANT SELECT ON ALL TABLES IN SCHEMA public
TO mcp_readonly_pagila;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres
IN SCHEMA public
GRANT SELECT ON TABLES TO mcp_readonly_pagila;
```

La configurazione consente all'utente di:

- collegarsi al database `pagila`;
- accedere allo schema `public`;
- eseguire interrogazioni di lettura sulle tabelle esistenti;
- ricevere automaticamente i privilegi SELECT sulle nuove tabelle create in futuro dal ruolo `postgres` nello schema `public`.

Non vengono assegnati privilegi di INSERT, UPDATE o DELETE sulle tabelle.

### 4.3 Verifica dei privilegi

La configurazione è stata verificata utilizzando le funzioni di controllo dei privilegi di PostgreSQL.

Query eseguita:

```sql
SELECT
    has_database_privilege(
        'mcp_readonly_pagila',
        'pagila',
        'CONNECT'
    ) AS can_connect,
    has_table_privilege(
        'mcp_readonly_pagila',
        'public.customer',
        'SELECT'
    ) AS can_select,
    has_table_privilege(
        'mcp_readonly_pagila',
        'public.customer',
        'INSERT'
    ) AS can_insert,
    has_table_privilege(
        'mcp_readonly_pagila',
        'public.customer',
        'UPDATE'
    ) AS can_update,
    has_table_privilege(
        'mcp_readonly_pagila',
        'public.customer',
        'DELETE'
    ) AS can_delete;
```

Risultato:

| Permesso | Risultato |
|---|---|
| CONNECT | `true` |
| SELECT | `true` |
| INSERT | `false` |
| UPDATE | `false` |
| DELETE | `false` |

La verifica conferma la corretta assegnazione dei privilegi previsti.

## 5. Configurazione DBHub

DBHub è il primo MCP Server utilizzato nel laboratorio sperimentale.

Repository:

https://github.com/bytebase/dbhub

Il server viene avviato localmente tramite Node.js e npm, utilizzando il pacchetto:

`@bytebase/dbhub`

La configurazione locale è conservata nel file:

`02_Laboratorio/dbhub/dbhub-pagila.toml`

Questo file contiene le credenziali di accesso al database e non deve essere pubblicato su GitHub.

È disponibile una configurazione di esempio senza credenziali:

`02_Laboratorio/dbhub/dbhub-pagila.toml.example`

### 5.1 Parametri di connessione

| Parametro | Valore |
|---|---|
| Source ID | `pagila` |
| Database type | PostgreSQL |
| Host | `127.0.0.1` |
| Porta | `5434` |
| Database | `pagila` |
| PostgreSQL role | `mcp_readonly_pagila` |
| Schema | `public` |
| Transport | stdio |

### 5.2 Tool configurati

Sono stati configurati due tool principali:

**execute_sql**

Utilizzato per l'esecuzione delle query SQL.

Parametri di sicurezza:

- `readonly = true`
- `max_rows = 1000`

La modalità read-only limita le operazioni SQL ammesse dal tool.

**search_objects**

Utilizzato per individuare gli oggetti presenti nel database, come tabelle e altri elementi dello schema.

### 5.3 Livelli di protezione

La configurazione utilizza due livelli indipendenti:

1. DBHub applica i propri controlli sulle operazioni SQL consentite.
2. PostgreSQL applica i privilegi associati all'utente `mcp_readonly_pagila`.

Questa configurazione permette di verificare il comportamento del sistema anche quando viene tentata un'operazione non consentita dal livello MCP.

## 6. Integrazione con Claude Desktop

Claude Desktop viene utilizzato come client MCP per interagire con il database tramite DBHub.

Architettura:

```text
Claude Desktop
      |
      v
   MCP Client
      |
      v
     DBHub
      |
      v
mcp_readonly_pagila
      |
      v
   PostgreSQL
      |
      v
     Pagila
```

Il server DBHub viene avviato da Claude Desktop utilizzando il transport `stdio`.

La configurazione del client è descritta nel documento:

`02_Laboratorio/client/claude-desktop.md`

## 7. Test sperimentali di sicurezza

Sono stati eseguiti test distinti per verificare i controlli applicati a livello MCP e quelli applicati direttamente da PostgreSQL.

### 7.1 Connessione tramite MCP

La connessione è stata verificata utilizzando Claude Desktop e il server MCP denominato `dbhub-thesis`.

Query:

```sql
SELECT current_database(), current_user;
```

Risultato:

| Campo | Valore |
|---|---|
| `current_database` | `pagila` |
| `current_user` | `mcp_readonly_pagila` |

La verifica conferma che DBHub utilizza il database e il ruolo PostgreSQL previsti.

### 7.2 Test del controllo read-only DBHub

Attraverso Claude Desktop è stata eseguita la seguente query:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

Risultato:

`999`

Successivamente è stato effettuato un tentativo di UPDATE:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE false;
```

DBHub ha rifiutato l'operazione prima di inviarla a PostgreSQL.

Errore restituito:

```text
code: READONLY_VIOLATION

Read-only mode is enabled.
Only the following SQL operations are allowed:
select, with, explain, show
```

È stata quindi eseguita nuovamente la query di conteggio:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

Risultato:

`999`

Il test dimostra il funzionamento del controllo read-only implementato a livello DBHub.

### 7.3 Test diretto dei privilegi PostgreSQL

Per verificare indipendentemente il comportamento di PostgreSQL, è stato effettuato un collegamento diretto al database utilizzando l'utente `mcp_readonly_pagila`, senza passare da DBHub.

Connessione:

```powershell
docker exec -it tesi-pagila psql -h 127.0.0.1 -U mcp_readonly_pagila -d pagila
```

Identificazione della connessione:

```sql
SELECT current_database(), current_user;
```

Risultato:

- database: `pagila`;
- utente: `mcp_readonly_pagila`.

È stata successivamente avviata una transazione:

```sql
BEGIN;
```

Tentativo di modifica:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE customer_id = 1;
```

PostgreSQL ha restituito:

```text
ERROR: permission denied for table customer
```

La transazione è stata annullata:

```sql
ROLLBACK;
```

Infine è stato eseguito nuovamente il conteggio:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

Risultato:

`999`

Il test dimostra che PostgreSQL rifiuta autonomamente l'operazione di UPDATE quando viene utilizzato un ruolo privo dei relativi privilegi.

### 7.4 Riepilogo dei risultati

| Test | Livello di controllo | Risultato |
|---|---|---|
| Connessione a Pagila | MCP / PostgreSQL | Superato |
| Lettura dei clienti | DBHub | Superato |
| Tentativo UPDATE tramite MCP | DBHub | Bloccato |
| Verifica dei privilegi PostgreSQL | Database | Superata |
| Tentativo UPDATE diretto | PostgreSQL | Bloccato |
| Verifica integrità dei dati | PostgreSQL | 999 clienti |

È importante distinguere i due test di scrittura:

- nel test tramite MCP, DBHub ha rifiutato la query in base alla propria modalità read-only;
- nel test diretto, PostgreSQL ha rifiutato l'UPDATE per mancanza dei privilegi dell'utente.

Il primo test non dimostra da solo il comportamento dei privilegi PostgreSQL, perché la query è stata respinta prima di raggiungere il database. Il secondo test verifica invece direttamente la protezione implementata dal DBMS.

### 7.5 Considerazioni

I risultati ottenuti mostrano l'efficacia di un approccio basato su più livelli di sicurezza.

DBHub limita le operazioni SQL ammesse attraverso la propria configurazione, mentre PostgreSQL applica autonomamente i privilegi associati all'utente utilizzato per la connessione.

La presenza di entrambi i controlli riduce il rischio che un errore di configurazione o un comportamento inatteso del livello MCP permetta all'agente di modificare i dati.

Questa configurazione rappresenta la baseline sperimentale del laboratorio e costituisce il riferimento per i successivi test comparativi tra differenti MCP Server.