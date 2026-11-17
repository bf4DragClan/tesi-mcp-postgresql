# Sicurezza dei database nell'interazione tra LLM e MCP Server

## 1. Introduzione

Questo repository raccoglie il materiale di ricerca e il laboratorio sperimentale sviluppati nell'ambito di una tesi dedicata alla sicurezza dell'accesso ai database relazionali da parte di applicazioni basate su Large Language Models (LLM) e agenti AI.

Il progetto si concentra sull'utilizzo del Model Context Protocol (MCP) come livello di comunicazione tra un agente AI e un database PostgreSQL.

L'obiettivo è analizzare i principali rischi di sicurezza che possono emergere quando un agente AI dispone di strumenti per interrogare o modificare un database e studiare le contromisure applicabili a livello di MCP Server e di DBMS.

## 2. Obiettivi della ricerca

Il progetto mira a:

- analizzare architetture e funzionalità di differenti MCP Server per database;
- identificare le principali superfici di attacco nell'interazione tra LLM e database;
- studiare autenticazione e autorizzazione;
- verificare il principio del Least Privilege;
- analizzare i controlli sulle operazioni SQL;
- studiare le vulnerabilità SQL Injection;
- confrontare query dinamiche e query parametrizzate;
- verificare l'efficacia di più livelli di protezione;
- realizzare un laboratorio riproducibile per test comparativi.

## 3. MCP Server analizzati

La fase di ricerca considera quattro implementazioni principali.

| MCP Server | Repository |
|---|---|
| DBHub | https://github.com/bytebase/dbhub |
| HenkDz PostgreSQL MCP Server | https://github.com/HenkDz/PostgreSQL-MCP-Server |
| CrystalDB PostgreSQL MCP Server | https://github.com/crystaldba/postgres-mcp |
| Google MCP Toolbox | https://github.com/googleapis/mcp-toolbox |

Le implementazioni vengono analizzate per caratteristiche architetturali, modalità di accesso ai database, strumenti disponibili e meccanismi di sicurezza.

Le analisi individuali e il confronto sono documentati nella directory `01_Ricerca_MCP`.

## 4. Struttura del repository

```text
Tesi MCP PostgreSQL/
│
├── 01_Ricerca_MCP/
│   ├── confronto.md
│   ├── dbhub.md
│   ├── henkdz-postgresql-mcp.md
│   ├── crystaldba-postgres-mcp.md
│   └── google-mcp-toolbox.md
│
├── 02_Laboratorio/
│   │
│   ├── client/
│   │   └── claude-desktop.md
│   │
│   ├── database/
│   │   ├── setup.md
│   │   ├── security_lab.sql
│   │   └── sql_injection_lab.sql
│   │
│   ├── dbhub/
│   │   ├── dbhub-pagila.toml.example
│   │   ├── dbhub-writer.toml.example
│   │   ├── dbhub-crud.toml.example
│   │   └── dbhub-sqli.toml.example
│   │
│   ├── pagila-source/
│   │
│   ├── .env.example
│   └── docker-compose.yml
│
├── .gitignore
└── README.md
```

La directory `pagila-source` è un Git submodule e contiene il codice e gli script del database Pagila.

Le configurazioni locali che contengono credenziali, come `.env.pagila` e i file TOML reali di DBHub, non vengono pubblicate su GitHub.

## 5. Laboratorio sperimentale

### 5.1 Database Pagila

Il laboratorio utilizza Pagila, un database di esempio basato su PostgreSQL e relativo a un sistema di noleggio cinematografico.

Repository:

https://github.com/devrimgunduz/pagila

Il database è eseguito tramite Docker Compose.

| Parametro | Valore |
|---|---|
| DBMS | PostgreSQL |
| Versione verificata | 18.6 |
| Database | `pagila` |
| Container | `tesi-pagila` |
| Porta host | `5434` |
| Volume | `02_laboratorio_pagila_data` |

### 5.2 Dati disponibili

Tra le principali tabelle del dataset:

| Tabella | Record |
|---|---:|
| `public.customer` | 999 |
| `public.film` | 1000 |
| `public.rental` | 51805 |
| `public.payment` | 51061 |
| `public.inventory` | 4581 |
| `public.actor` | 200 |

### 5.3 Schema sperimentale

Per gli esperimenti è stato creato lo schema:

`security_lab`

Lo schema contiene due tabelle sintetiche:

- `test_customers`;
- `test_accounts`.

Le tabelle contengono quattro record iniziali ciascuna.

Questa separazione consente di eseguire test CRUD e SQL Injection senza alterare il dataset originale Pagila.

## 6. Ruoli e autorizzazioni PostgreSQL

Sono stati configurati tre ruoli PostgreSQL con privilegi differenti.

| Ruolo | SELECT | INSERT | UPDATE | DELETE |
|---|---:|---:|---:|---:|
| `mcp_readonly_pagila` | Sì | No | No | No |
| `mcp_writer_pagila` | Sì | Sì | Sì | No |
| `mcp_crud_pagila` | Sì | Sì | Sì | Sì |

I ruoli Writer e CRUD operano esclusivamente nello schema sperimentale `security_lab`.

Il ruolo read-only viene utilizzato anche per l'accesso in lettura allo schema originale `public` di Pagila.

Tutti e tre i ruoli non dispongono del privilegio TRUNCATE né di privilegi amministrativi.

La configurazione permette di studiare il principio del Least Privilege e gli effetti di differenti livelli di autorizzazione.

## 7. Integrazione con DBHub e Claude Desktop

DBHub costituisce il primo MCP Server integrato nel laboratorio.

Claude Desktop viene utilizzato come client MCP.

L'architettura generale è:

```text
              Claude Desktop
                    |
                    v
                 MCP Client
                    |
          +---------+---------+
          |         |         |
          v         v         v
    dbhub-thesis dbhub-writer dbhub-crud
          |         |         |
          v         v         v
       PostgreSQL PostgreSQL PostgreSQL
          |         |         |
          +---------+---------+
                    |
                    v
                  Pagila
```

È stata configurata anche una quarta connessione:

`dbhub-sqli`

Questa è dedicata esclusivamente all'esperimento SQL Injection e utilizza due custom tool.

### 7.1 Connessioni verificate

| Server MCP | Ruolo PostgreSQL | Utilizzo |
|---|---|---|
| `dbhub-thesis` | `mcp_readonly_pagila` | Sola lettura |
| `dbhub-writer` | `mcp_writer_pagila` | INSERT e UPDATE |
| `dbhub-crud` | `mcp_crud_pagila` | Operazioni CRUD |
| `dbhub-sqli` | `mcp_readonly_pagila` | Test SQL Injection |

Per ogni connessione è stata verificata l'identità dell'utente PostgreSQL mediante:

```sql
SELECT current_database(), current_user;
```

I risultati hanno confermato che ogni server utilizza il ruolo previsto.

## 8. Risultati sperimentali CRUD

Le autorizzazioni PostgreSQL sono state verificate direttamente e successivamente attraverso DBHub e Claude Desktop.

### 8.1 Test read-only

Attraverso `dbhub-thesis`:

- SELECT eseguita correttamente;
- tentativo di UPDATE rifiutato con `READONLY_VIOLATION`;
- numero dei clienti originali rimasto pari a 999.

Un successivo test diretto su PostgreSQL ha restituito:

`ERROR: permission denied for table customer`

Questo ha verificato che anche il DBMS impedisce autonomamente l'UPDATE.

### 8.2 Test writer

Attraverso `dbhub-writer`:

- INSERT consentito;
- UPDATE consentito;
- DELETE rifiutato da PostgreSQL.

È stato inserito un record temporaneo con ID 9010, successivamente aggiornato.

Il tentativo di eliminazione è stato respinto e il record è rimasto presente.

### 8.3 Test CRUD

Attraverso `dbhub-crud`:

- INSERT consentito;
- UPDATE consentito;
- DELETE consentito.

È stato eliminato il record temporaneo 9010, inserito il record 9020, modificato e successivamente eliminato.

La verifica finale ha confermato che il record 9020 non era più presente.

I test hanno confermato il comportamento atteso dei tre profili di autorizzazione.

## 9. Esperimento SQL Injection

È stato realizzato un esperimento dedicato allo studio delle vulnerabilità SQL Injection.

L'esperimento utilizza due funzioni PostgreSQL:

- `security_lab.search_customer_unsafe`;
- `security_lab.search_customer_safe`.

La prima costruisce dinamicamente una query concatenando direttamente l'input ricevuto.

La seconda utilizza una query statica parametrizzata.

Entrambe vengono esposte attraverso il server DBHub `dbhub-sqli`.

### 9.1 Funzione vulnerabile

È stato utilizzato il payload:

```text
x' OR '1'='1
```

Il custom tool `search_customer_unsafe` ha restituito tutti e quattro i clienti presenti nella tabella sperimentale, invece di filtrare i risultati.

Il test ha confermato la vulnerabilità SQL Injection.

### 9.2 Funzione parametrizzata

Lo stesso input è stato utilizzato con `search_customer_safe`.

Risultato:

`0 record`

La funzione ha trattato l'intero input come valore letterale, senza modificarne la struttura SQL.

### 9.3 Test UNION-based

È stata inoltre verificata una SQL Injection basata su UNION.

Il test ha permesso di individuare una struttura a quattro colonne e recuperare informazioni sull'istanza PostgreSQL:

- database: `pagila`;
- utente: `mcp_readonly_pagila`;
- versione: PostgreSQL 18.6.

Il payload UNION esatto non è stato conservato nel resoconto sperimentale.

### 9.4 Interpretazione

L'esperimento dimostra che:

- una query dinamica costruita concatenando input non affidabili può essere vulnerabile;
- una SELECT vulnerabile può restituire dati non previsti anche con un ruolo read-only;
- il parametro `$1` del tool MCP non corregge automaticamente una funzione PostgreSQL che concatena internamente il parametro;
- una query statica parametrizzata evita il comportamento osservato nella funzione vulnerabile.

La documentazione completa è contenuta in:

`02_Laboratorio/database/sql_injection_lab.md`

## 10. Avvio del laboratorio

Dopo aver clonato il repository, inizializzare il submodule Pagila:

```powershell
git submodule update --init --recursive
```

Spostarsi nella directory:

```powershell
cd 02_Laboratorio
```

Creare il file locale delle variabili d'ambiente:

```powershell
Copy-Item .env.example .env.pagila
```

Inserire la password amministrativa PostgreSQL in