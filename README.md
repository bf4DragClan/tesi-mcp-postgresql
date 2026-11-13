# Sicurezza dei database nell'interazione con LLM tramite MCP Server

## 1. Introduzione

Questo repository contiene il materiale di ricerca e il laboratorio sperimentale sviluppati nell'ambito di una tesi dedicata alla sicurezza dell'accesso ai database relazionali da parte di applicazioni basate su Large Language Models (LLM) e agenti AI.

Il progetto si concentra sull'utilizzo del Model Context Protocol (MCP) come livello di comunicazione tra un agente AI e un database PostgreSQL.

L'obiettivo è analizzare i rischi di sicurezza che possono emergere quando un agente AI dispone di strumenti per interrogare o modificare un database e studiare le contromisure implementate a livello di MCP Server e di DBMS.

## 2. Obiettivi della ricerca

Il progetto mira a:

- analizzare l'architettura e il funzionamento di diversi MCP Server per database;
- individuare le principali superfici di attacco nell'interazione tra LLM e database;
- studiare i meccanismi di autenticazione e autorizzazione;
- analizzare il principio del Least Privilege;
- verificare l'efficacia dei controlli read-only;
- confrontare le garanzie di sicurezza offerte da differenti implementazioni MCP;
- realizzare un laboratorio riproducibile per effettuare test sperimentali.

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
│   │   └── setup.md
│   │
│   ├── dbhub/
│   │   └── dbhub-pagila.toml.example
│   │
│   ├── pagila-source/
│   │
│   ├── .env.example
│   └── docker-compose.yml
│
├── .gitignore
└── README.md
```

La directory `pagila-source` è un Git submodule e contiene il codice e gli script del progetto Pagila.

Le configurazioni locali che contengono credenziali, come `.env.pagila` e `dbhub-pagila.toml`, non vengono versionate.

## 5. Laboratorio sperimentale

### 5.1 Database

Il laboratorio utilizza Pagila, un database di esempio basato su PostgreSQL e relativo a un sistema di noleggio cinematografico.

Repository:

https://github.com/devrimgunduz/pagila

Il database viene eseguito tramite Docker Compose.

| Parametro | Valore |
|---|---|
| DBMS | PostgreSQL |
| Versione verificata | 18.6 |
| Database | `pagila` |
| Container | `tesi-pagila` |
| Porta host | `5434` |
| Volume | `02_laboratorio_pagila_data` |

Il dataset contiene diverse tabelle relazionali utilizzate per gli esperimenti.

Tra i dati verificati:

| Tabella | Record |
|---|---:|
| `customer` | 999 |
| `film` | 1000 |
| `rental` | 51805 |
| `payment` | 51061 |
| `inventory` | 4581 |
| `actor` | 200 |

### 5.2 Ruolo PostgreSQL dedicato

Per l'accesso tramite MCP Server è stato creato il ruolo:

`mcp_readonly_pagila`

Il ruolo dispone dei privilegi necessari per connettersi al database ed eseguire operazioni di lettura sulle tabelle dello schema `public`.

Non dispone dei privilegi di INSERT, UPDATE e DELETE sulle tabelle.

L'utilizzo di un account dedicato permette di applicare il principio del Least Privilege e di evitare che l'MCP Server utilizzi direttamente l'account amministrativo PostgreSQL.

### 5.3 DBHub

DBHub costituisce il primo MCP Server integrato nel laboratorio.

La configurazione utilizza:

- transport `stdio`;
- database PostgreSQL `pagila`;
- ruolo `mcp_readonly_pagila`;
- tool `execute_sql` in modalità read-only;
- limite massimo di 1000 righe;
- tool `search_objects`.

La configurazione locale contenente le credenziali è esclusa da Git. Nel repository è presente solamente il relativo file di esempio.

### 5.4 Claude Desktop

Claude Desktop viene utilizzato come client MCP per interagire con DBHub.

L'applicazione avvia localmente il server tramite Node.js e stabilisce la comunicazione attraverso il transport `stdio`.

L'integrazione permette di formulare richieste in linguaggio naturale e utilizzare i tool MCP per interrogare il database PostgreSQL.

La configurazione è descritta in:

`02_Laboratorio/client/claude-desktop.md`

## 6. Risultati sperimentali iniziali

È stata verificata la prima integrazione end-to-end:

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

### 6.1 Verifica della connessione

Attraverso DBHub è stata eseguita:

```sql
SELECT current_database(), current_user;
```

Risultato:

| Campo | Valore |
|---|---|
| Database | `pagila` |
| Utente | `mcp_readonly_pagila` |

### 6.2 Controllo read-only DBHub

È stata eseguita una query di lettura sulla tabella `public.customer`, che ha restituito 999 record.

Un successivo tentativo di UPDATE è stato rifiutato da DBHub con il codice:

`READONLY_VIOLATION`

Il server ha indicato che, in modalità read-only, sono ammesse soltanto le operazioni SELECT, WITH, EXPLAIN e SHOW.

Il conteggio dei clienti è rimasto pari a 999.

### 6.3 Controllo dei privilegi PostgreSQL

È stato effettuato un test indipendente collegandosi direttamente al database con l'utente `mcp_readonly_pagila`, senza passare attraverso DBHub.

Il tentativo di UPDATE sulla tabella `public.customer` è stato rifiutato da PostgreSQL con:

`ERROR: permission denied for table customer`

La transazione è stata annullata tramite ROLLBACK.

Il conteggio finale dei clienti è rimasto pari a 999.

### 6.4 Interpretazione

I test hanno verificato due livelli di protezione distinti:

1. DBHub blocca le operazioni SQL non ammesse dalla propria configurazione read-only.
2. PostgreSQL impedisce autonomamente le operazioni non autorizzate in base ai privilegi del ruolo.

I risultati costituiscono una prima evidenza sperimentale dell'utilità della difesa a più livelli (*defense in depth*).

Questa baseline sarà utilizzata come riferimento per i successivi esperimenti comparativi.

## 7. Avvio del laboratorio

Per inizializzare il submodule Pagila dopo aver clonato il repository:

```powershell
git submodule update --init --recursive
```

Per configurare l'ambiente, dalla directory `02_Laboratorio` copiare il file di esempio:

```powershell
Copy-Item .env.example .env.pagila
```

Impostare la password amministrativa PostgreSQL in `.env.pagila`.

Per avviare il container:

```powershell
docker compose --env-file .env.pagila up -d --build
```

Per verificare lo stato:

```powershell
docker compose --env-file .env.pagila ps
```

Per arrestare il container preservando i dati:

```powershell
docker compose --env-file .env.pagila down
```

Le credenziali locali non devono essere inserite nei commit o pubblicate su GitHub.

## 8. Documentazione

Per ulteriori dettagli:

- `01_Ricerca_MCP/confronto.md`: confronto tra gli MCP Server analizzati.
- `01_Ricerca_MCP/`: analisi individuali delle implementazioni.
- `02_Laboratorio/database/setup.md`: configurazione completa del database e risultati dei test.
- `02_Laboratorio/client/claude-desktop.md`: integrazione con Claude Desktop.
- `02_Laboratorio/dbhub/dbhub-pagila.toml.example`: esempio di configurazione DBHub.

## 9. Sviluppi successivi

Le attività successive previste dal progetto includono:

- approfondimento delle superfici di attacco degli MCP Server selezionati;
- configurazione degli ulteriori MCP Server sul database Pagila;
- progettazione di scenari sperimentali comuni;
- confronto delle modalità di autenticazione e autorizzazione;
- analisi dei controlli sulle query SQL;
- verifica della gestione dei privilegi e delle operazioni potenzialmente pericolose;
- valutazione delle garanzie di sicurezza offerte dalle diverse architetture.

L'obiettivo finale è individuare i principali rischi associati all'accesso ai database da parte di agenti AI e valutare sperimentalmente l'efficacia delle contromisure disponibili.