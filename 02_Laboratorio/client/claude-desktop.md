# Claude Desktop – Configurazione del laboratorio MCP

## 1. Obiettivo

Claude Desktop viene utilizzato come client MCP per verificare l'interazione tra un agente basato su Large Language Model (LLM), diversi MCP Server e un database PostgreSQL.

Nel laboratorio, Claude Desktop comunica con DBHub attraverso il Model Context Protocol (MCP).

DBHub espone strumenti per interrogare il database e, a seconda della configurazione e dei privilegi PostgreSQL utilizzati, eseguire differenti operazioni.

L'obiettivo è confrontare il comportamento dei diversi profili di autorizzazione e verificare alcuni scenari di sicurezza.

## 2. Architettura

L'architettura generale è:

```text
                  Utente
                    |
                    v
             Claude Desktop
                    |
                    v
                MCP Client
                    |
        +-----------+-----------+
        |           |           |
        v           v           v
   dbhub-thesis dbhub-writer dbhub-crud
        |           |           |
        v           v           v
    PostgreSQL  PostgreSQL  PostgreSQL
   read-only     writer       CRUD
        |           |           |
        +-----------+-----------+
                    |
                    v
                  Pagila
                 /      \
             public  security_lab
```

Per l'esperimento SQL Injection viene utilizzata una quarta connessione DBHub, denominata `dbhub-sqli`, che espone due custom tool dedicati.

## 3. Componenti utilizzati

### 3.1 Claude Desktop

Claude Desktop è utilizzato come applicazione client MCP.

L'applicazione consente di configurare server MCP locali e utilizzare i relativi tool durante le conversazioni.

La configurazione viene gestita da:

`Settings → Developer → Edit Config`

Il server viene avviato localmente tramite Node.js.

### 3.2 DBHub

DBHub è l'MCP Server utilizzato per accedere a PostgreSQL.

Repository:

https://github.com/bytebase/dbhub

Il pacchetto viene avviato tramite npm:

`@bytebase/dbhub`

Il transport utilizzato nel laboratorio è `stdio`.

La configurazione di ogni server è contenuta in un file TOML distinto.

### 3.3 PostgreSQL e Pagila

Il database viene eseguito tramite Docker.

| Parametro | Valore |
|---|---|
| Container | `tesi-pagila` |
| Database | `pagila` |
| Host | `127.0.0.1` |
| Porta | `5434` |
| Versione PostgreSQL verificata | 18.6 |

Gli account PostgreSQL utilizzati dagli MCP Server sono distinti in base al profilo di autorizzazione.

## 4. Server MCP configurati

Sono state configurate quattro connessioni indipendenti.

### 4.1 dbhub-thesis

Configurazione:

`02_Laboratorio/dbhub/dbhub-pagila.toml`

Ruolo PostgreSQL:

`mcp_readonly_pagila`

Caratteristiche:

- accesso al database Pagila;
- lettura delle tabelle originali;
- accesso in lettura alle tabelle sperimentali;
- tool `execute_sql` in modalità `readonly = true`;
- tool `search_objects`.

Questa connessione costituisce la baseline read-only del laboratorio.

### 4.2 dbhub-writer

Configurazione:

`02_Laboratorio/dbhub/dbhub-writer.toml`

Ruolo PostgreSQL:

`mcp_writer_pagila`

Caratteristiche:

- accesso allo schema `security_lab`;
- SELECT;
- INSERT;
- UPDATE;
- nessun privilegio DELETE;
- tool `execute_sql` configurato con `readonly = false`;
- tool `search_objects`.

DBHub permette l'esecuzione delle operazioni di scrittura, mentre PostgreSQL applica le autorizzazioni del ruolo.

### 4.3 dbhub-crud

Configurazione:

`02_Laboratorio/dbhub/dbhub-crud.toml`

Ruolo PostgreSQL:

`mcp_crud_pagila`

Caratteristiche:

- accesso allo schema `security_lab`;
- SELECT;
- INSERT;
- UPDATE;
- DELETE;
- nessun privilegio TRUNCATE;
- tool `execute_sql` configurato con `readonly = false`;
- tool `search_objects`.

Questa connessione viene utilizzata per verificare le operazioni CRUD complete.

### 4.4 dbhub-sqli

Configurazione:

`02_Laboratorio/dbhub/dbhub-sqli.toml`

Ruolo PostgreSQL:

`mcp_readonly_pagila`

Caratteristiche:

- accesso in sola lettura;
- schema di lavoro `security_lab`;
- nessun tool SQL generico `execute_sql`;
- esposizione di due custom tool:
  - `search_customer_unsafe`;
  - `search_customer_safe`.

La connessione è dedicata all'esperimento SQL Injection.

Le due funzioni PostgreSQL sottostanti utilizzano rispettivamente SQL dinamico vulnerabile e SQL statico parametrizzato.

## 5. Configurazione di Claude Desktop

Il file di configurazione viene aperto direttamente da Claude Desktop attraverso:

`Settings → Developer → Edit Config`

La sezione `mcpServers` contiene le connessioni MCP.

Esempio:

```json
{
  "mcpServers": {
    "dbhub-thesis": {
      "command": "npx",
      "args": [
        "-y",
        "@bytebase/dbhub@latest",
        "--transport",
        "stdio",
        "--config",
        "C:\\PERCORSO\\PROGETTO\\02_Laboratorio\\dbhub\\dbhub-pagila.toml"
      ]
    },
    "dbhub-writer": {
      "command": "npx",
      "args": [
        "-y",
        "@bytebase/dbhub@latest",
        "--transport",
        "stdio",
        "--config",
        "C:\\PERCORSO\\PROGETTO\\02_Laboratorio\\dbhub\\dbhub-writer.toml"
      ]
    },
    "dbhub-crud": {
      "command": "npx",
      "args": [
        "-y",
        "@bytebase/dbhub@latest",
        "--transport",
        "stdio",
        "--config",
        "C:\\PERCORSO\\PROGETTO\\02_Laboratorio\\dbhub\\dbhub-crud.toml"
      ]
    },
    "dbhub-sqli": {
      "command": "npx",
      "args": [
        "-y",
        "@bytebase/dbhub@latest",
        "--transport",
        "stdio",
        "--config",
        "C:\\PERCORSO\\PROGETTO\\02_Laboratorio\\dbhub\\dbhub-sqli.toml"
      ]
    }
  }
}
```

Il percorso deve essere sostituito con quello effettivo del progetto sul computer utilizzato.

Se il file contiene altre preferenze o server MCP, queste devono essere mantenute.

Dopo ogni modifica alla configurazione è necessario salvare il file e riavviare completamente Claude Desktop.

## 6. Verifica dell'identità delle connessioni

Per verificare che ogni server utilizzi il corretto account PostgreSQL è stata eseguita la seguente query:

```sql
SELECT current_database(), current_user;
```

Risultati ottenuti:

| Server MCP | Database | Utente PostgreSQL |
|---|---|---|
| `dbhub-thesis` | `pagila` | `mcp_readonly_pagila` |
| `dbhub-writer` | `pagila` | `mcp_writer_pagila` |
| `dbhub-crud` | `pagila` | `mcp_crud_pagila` |
| `dbhub-sqli` | `pagila` | `mcp_readonly_pagila` |

La verifica dimostra che le connessioni utilizzano effettivamente identità PostgreSQL differenti.

## 7. Test tramite dbhub-thesis

È stata verificata la lettura dei dati originali di Pagila.

La query:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

ha restituito:

`999`

È stato successivamente tentato un UPDATE:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE false;
```

DBHub ha respinto la query con:

```text
code: READONLY_VIOLATION

Read-only mode is enabled.
Only the following SQL operations are allowed:
select, with, explain, show
```

Una nuova SELECT ha confermato che i clienti erano ancora 999.

## 8. Test tramite dbhub-writer

Il profilo writer è stato utilizzato sulla tabella:

`security_lab.test_customers`

### 8.1 INSERT

È stato inserito un record temporaneo:

| Campo | Valore |
|---|---|
| customer_id | 9010 |
| first_name | Claude |
| last_name | Writer |
| email | claude.writer@example.test |
| notes | MCP writer test |

L'inserimento è riuscito ed è stato verificato con una SELECT.

### 8.2 UPDATE

Il campo `notes` è stato aggiornato al valore:

`Updated through DBHub Writer`

L'aggiornamento è riuscito.

### 8.3 DELETE

È stato tentato un DELETE sul record 9010.

PostgreSQL ha restituito:

```text
error: permission denied for table test_customers
code: EXECUTION_ERROR
```

Una SELECT successiva ha confermato che il record era ancora presente.

Il test dimostra che il ruolo writer può inserire e modificare record, ma non eliminarli.

## 9. Test tramite dbhub-crud

Il profilo CRUD è stato utilizzato per verificare tutte le operazioni.

Le operazioni eseguite sono state:

1. eliminazione del record temporaneo 9010;
2. inserimento di un nuovo record con ID 9020;
3. aggiornamento del campo `notes`;
4. verifica del record aggiornato;
5. eliminazione del record 9020;
6. verifica dell'assenza del record.

L'inserimento e l'aggiornamento sono riusciti.

Entrambi i DELETE sono stati eseguiti correttamente.

La verifica finale ha restituito zero righe per il record 9020.

Il test conferma il funzionamento del profilo CRUD.

## 10. Esperimento SQL Injection tramite dbhub-sqli

Il server `dbhub-sqli` è dedicato alla verifica di due implementazioni della ricerca di clienti.

I custom tool disponibili sono:

- `search_customer_unsafe`;
- `search_customer_safe`.

Entrambi ricevono un parametro stringa denominato `last_name`.

### 10.1 Ricerca normale

Utilizzando `search_customer_unsafe` con:

`Lovelace`

è stato restituito un singolo record:

Ada Lovelace.

### 10.2 SQL Injection sulla funzione vulnerabile

È stato passato il seguente valore:

```text
x' OR '1'='1
```

Il custom tool `search_customer_unsafe` ha restituito tutti e quattro i clienti presenti nella tabella sperimentale.

Il test conferma che la concatenazione dell'input nella query dinamica permette di alterare la condizione WHERE.

### 10.3 Verifica della funzione sicura

È stato utilizzato lo stesso valore con `search_customer_safe`.

Risultato:

`0 record`

La funzione ha trattato l'intero input come valore letterale del parametro e non come codice SQL.

### 10.4 UNION-based SQL Injection

È stato inoltre eseguito un test di tipo UNION sul custom tool vulnerabile.

Durante il test è stato individuato il numero di colonne atteso dalla funzione, pari a quattro.

La verifica ha permesso di ottenere:

| Informazione | Risultato |
|---|---|
| Database corrente | `pagila` |
| Utente corrente | `mcp_readonly_pagila` |
| Versione PostgreSQL | 18.6 |

Il payload UNION esatto non è stato conservato nel resoconto dell'esperimento e non viene ricostruito in questo documento.

## 11. Considerazioni finali

L'integrazione ha permesso di verificare quattro server MCP distinti, collegati allo stesso database ma autenticati con differenti identità PostgreSQL.

I test CRUD hanno confermato che i privilegi del DBMS vengono applicati anche quando le query vengono eseguite tramite DBHub.

L'esperimento SQL Injection ha inoltre dimostrato che una connessione read-only può comunque essere vulnerabile a problemi di integrità della costruzione delle query e di esposizione dei dati.

La parametrizzazione del tool MCP non protegge automaticamente una funzione PostgreSQL che utilizza SQL dinamico concatenando input non affidabili.

La configurazione costituisce una baseline sperimentale per i successivi confronti tra differenti MCP Server.

