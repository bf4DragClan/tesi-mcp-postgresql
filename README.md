# Sicurezza dei database nell'interazione tra LLM e MCP Server

## 1. Introduzione

Questo repository raccoglie il materiale di ricerca e il laboratorio sperimentale sviluppati nell'ambito di una tesi sulla **sicurezza dell'accesso ai database relazionali da parte di applicazioni basate su Large Language Models (LLM) e agenti AI**.

Il progetto studia l'impiego del **Model Context Protocol (MCP)** come interfaccia tra un agente AI e PostgreSQL, con particolare attenzione ai controlli di autorizzazione, alla costruzione delle query SQL e alle possibili vulnerabilità. La sperimentazione si svolge in un ambiente locale e controllato, utilizzando dati sintetici per le operazioni potenzialmente modificative.

## 2. Obiettivi della ricerca

Gli obiettivi principali sono:

- analizzare architetture, funzionalità e superfici di attacco di differenti MCP Server per database;
- studiare autenticazione, autorizzazione e principio del **Least Privilege**;
- distinguere i controlli applicati dal server MCP da quelli imposti dal DBMS;
- verificare l'efficacia dei controlli read-only anche rispetto a scritture indirette;
- analizzare il rischio di **SQL injection** nei custom tool e nei tool predefiniti;
- confrontare SQL dinamico vulnerabile e query parametrizzate;
- produrre risultati sperimentali documentati e riproducibili.

## 3. MCP Server analizzati

La fase di ricerca considera quattro implementazioni:

| MCP Server | Repository |
|---|---|
| DBHub | [bytebase/dbhub](https://github.com/bytebase/dbhub) |
| HenkDz PostgreSQL MCP Server | [HenkDz/PostgreSQL-MCP-Server](https://github.com/HenkDz/PostgreSQL-MCP-Server) |
| CrystalDB PostgreSQL MCP Server | [crystaldba/postgres-mcp](https://github.com/crystaldba/postgres-mcp) |
| Google MCP Toolbox | [googleapis/mcp-toolbox](https://github.com/googleapis/mcp-toolbox) |

Le analisi individuali e il confronto si trovano in [`01_Ricerca_MCP/`](01_Ricerca_MCP/). **DBHub è il server utilizzato per gli esperimenti descritti in questo README**; l'analisi degli altri progetti costituisce una distinta attività di ricerca.

## 4. Struttura del repository

```text
Tesi MCP PostgreSQL/
├── 01_Ricerca_MCP/
│   ├── confronto.md
│   ├── dbhub.md
│   ├── henkdz-postgresql-mcp.md
│   ├── crystaldba-postgres-mcp.md
│   └── google-mcp-toolbox.md
├── 02_Laboratorio/
│   ├── client/
│   │   └── claude-desktop.md
│   ├── database/
│   │   ├── setup.md
│   │   ├── security_lab.sql
│   │   ├── sql_injection_lab.sql
│   │   ├── sql_injection_lab.md
│   │   └── dbhub_security_tests.md
│   ├── dbhub/
│   │   ├── dbhub-pagila.toml.example
│   │   ├── dbhub-writer.toml.example
│   │   ├── dbhub-crud.toml.example
│   │   ├── dbhub-sqli.toml.example
│   │   └── dbhub-readonly-writer.toml.example
│   ├── pagila-source/                 # Git submodule
│   ├── .env.example
│   └── docker-compose.yml
├── .gitignore
└── README.md
```

La directory `pagila-source` è un **Git submodule** del progetto [Pagila](https://github.com/devrimgunduz/pagila). I file `.toml.example` sono modelli senza credenziali; i corrispondenti TOML reali e `.env.pagila` rimangono locali e non devono essere pubblicati.

## 5. Laboratorio PostgreSQL e Pagila

### 5.1 Ambiente

| Componente | Configurazione |
|---|---|
| DBMS | PostgreSQL 18.6 (versione verificata nel laboratorio) |
| Database | `pagila` |
| Container Docker | `tesi-pagila` |
| Host | `127.0.0.1` |
| Porta host | `5434` |
| Volume Docker | `02_laboratorio_pagila_data` |
| Client MCP | Claude Desktop |
| MCP Server sperimentale | DBHub (`@bytebase/dbhub`) |

Il database Pagila simula un sistema di noleggio cinematografico. Sono stati verificati i seguenti conteggi di riferimento:

| Tabella | Record |
|---|---:|
| `public.customer` | 999 |
| `public.film` | 1.000 |
| `public.rental` | 51.805 |
| `public.payment` | 51.061 |
| `public.inventory` | 4.581 |
| `public.actor` | 200 |

### 5.2 Separazione degli schemi

- **`public`**: contiene le tabelle originali Pagila, utilizzate prevalentemente in lettura.
- **`security_lab`**: contiene le tabelle e le funzioni sperimentali, senza intervenire sui dati originali.

Lo schema `security_lab` comprende `test_customers` e `test_accounts` (quattro record sintetici iniziali ciascuna) e `mcp_readonly_probe`, tabella con un contatore utilizzata per verificare le scritture indirette. Sono inoltre presenti le funzioni per il test SQL injection e `readonly_write_probe()`.

Lo script [`security_lab.sql`](02_Laboratorio/database/security_lab.sql) definisce le tabelle sperimentali, i ruoli writer/CRUD, i relativi privilegi e la funzione per il confronto read-only. Lo script dedicato alla SQL injection è [`sql_injection_lab.sql`](02_Laboratorio/database/sql_injection_lab.sql).

## 6. Ruoli e autorizzazioni PostgreSQL

Il laboratorio utilizza tre account non amministrativi. La tabella seguente descrive i privilegi di riferimento sulle **tabelle sperimentali** dello schema `security_lab`.

| Ruolo PostgreSQL | SELECT | INSERT | UPDATE | DELETE |
|---|:---:|:---:|:---:|:---:|
| `mcp_readonly_pagila` | Sì | No | No | No |
| `mcp_writer_pagila` | Sì | Sì | Sì | No |
| `mcp_crud_pagila` | Sì | Sì | Sì | Sì |

Il ruolo read-only è utilizzato anche per leggere i dati originali di Pagila nello schema `public`. I profili writer e CRUD sono limitati allo schema di laboratorio e non hanno privilegi amministrativi. I permessi di esecuzione delle funzioni vengono concessi separatamente dove necessario.

Questa separazione consente di distinguere i rifiuti dovuti alla **policy MCP** da quelli dovuti ai **privilegi PostgreSQL**.

## 7. Integrazione DBHub e Claude Desktop

Claude Desktop comunica con i server DBHub tramite MCP, utilizzando il transport `stdio`. Sono state configurate **cinque connessioni MCP**, tutte dirette al database Pagila ma con differenti identità e policy.

```text
Claude Desktop (client MCP)
        |
        +-- dbhub-thesis ----------> mcp_readonly_pagila     (execute_sql read-only)
        +-- dbhub-writer ----------> mcp_writer_pagila       (execute_sql scrivibile)
        +-- dbhub-crud ------------> mcp_crud_pagila         (execute_sql scrivibile)
        +-- dbhub-sqli ------------> mcp_readonly_pagila     (custom tool SQL injection)
        +-- dbhub-readonly-writer -> mcp_writer_pagila       (execute_sql read-only)
                                              |
                                              v
                                    PostgreSQL / pagila
                                    public + security_lab
```

| Server MCP | Ruolo PostgreSQL | `execute_sql` | Finalità |
|---|---|---|---|
| `dbhub-thesis` | `mcp_readonly_pagila` | `readonly = true` | Baseline con lettura limitata su entrambi i livelli |
| `dbhub-writer` | `mcp_writer_pagila` | `readonly = false` | Prove INSERT/UPDATE e verifica dei limiti DBMS |
| `dbhub-crud` | `mcp_crud_pagila` | `readonly = false` | Prove CRUD complete |
| `dbhub-sqli` | `mcp_readonly_pagila` | Non esposto come tool generico | Custom tool `search_customer_safe` e `search_customer_unsafe` |
| **`dbhub-readonly-writer`** | **`mcp_writer_pagila`** | **`readonly = true`** | **Isolare l'efficacia del controllo read-only del tool MCP** |

I profili `dbhub-writer` e `dbhub-readonly-writer` usano **lo stesso account PostgreSQL**. Cambiando soltanto la policy MCP si può attribuire al server il diverso trattamento delle query e delle transazioni.

I file modello sono nella cartella [`02_Laboratorio/dbhub/`](02_Laboratorio/dbhub/), mentre istruzioni e configurazione di Claude Desktop sono in [`client/claude-desktop.md`](02_Laboratorio/client/claude-desktop.md).

**Versioni:** nella cache npm locale è stata individuata DBHub `1.7.1`; la nuova configurazione `dbhub-readonly-writer` è stata impostata con `@bytebase/dbhub@1.7.1`. Le quattro configurazioni precedenti sono state documentate con `@latest`. Cache e configurazione non costituiscono, da sole, prova indipendente della versione del processo avviato: questo limite è registrato nella documentazione sperimentale.

## 8. Risultati sperimentali sui permessi PostgreSQL

### 8.1 Profilo read-only

Con `dbhub-thesis`, la lettura di `public.customer` ha restituito **999 record**. Il tentativo di `UPDATE` è stato respinto da DBHub con `READONLY_VIOLATION`.

Un test diretto su PostgreSQL con `mcp_readonly_pagila` ha restituito `permission denied for table customer`, evidenziando anche l'efficacia indipendente dei privilegi del DBMS.

### 8.2 Profilo writer

Con `dbhub-writer` sono stati verificati un `INSERT` e un `UPDATE` nella tabella `security_lab.test_customers`. Un tentativo di `DELETE` è stato invece rifiutato da PostgreSQL con un errore di autorizzazione.

### 8.3 Profilo CRUD

Con `dbhub-crud` sono state eseguite correttamente operazioni `INSERT`, `UPDATE` e `DELETE` sui record temporanei. La verifica finale ha confermato l'assenza dei record creati durante le prove.

## 9. Verifica del controllo read-only di DBHub

Per rispondere alla domanda sull'efficacia dei controlli del **server MCP**, è stato creato il profilo `dbhub-readonly-writer`: DBHub ha il tool `execute_sql` in sola lettura, mentre l'utente PostgreSQL conserva i permessi di scrittura sulle tabelle di prova.

| Esperimento | Risultato osservato |
|---|---|
| Identità della connessione | `pagila`, `mcp_writer_pagila` |
| `UPDATE` diretto | Bloccato con `READONLY_VIOLATION` |
| `WITH` contenente un `UPDATE` | Bloccata con `READONLY_VIOLATION` |
| `transaction_read_only` sul profilo read-only | `on` |
| `transaction_read_only` sul profilo writer | `off` |
| `SELECT` che invoca una funzione con `UPDATE` interno, su writer | Contatore da `0` a `1` |
| Stessa funzione, su read-only-writer | `cannot execute UPDATE in a read-only transaction`; contatore fermo a `1` |

La funzione di prova `security_lab.readonly_write_probe()` è `VOLATILE` e `SECURITY INVOKER`, quindi non utilizza privilegi maggiori di quelli del chiamante.

**Interpretazione:** i test mostrano due meccanismi complementari nella configurazione esaminata: rifiuto delle istruzioni non consentite e protezione della transazione PostgreSQL. Una query apparentemente di lettura che richiama una funzione con effetti collaterali non è riuscita a modificare il contatore nel profilo read-only. Questi risultati non dimostrano l'impossibilità di ogni possibile aggiramento.

Per query, risposte, errori e limiti vedere [`dbhub_security_tests.md`](02_Laboratorio/database/dbhub_security_tests.md).

### 9.1 Vulnerabilità storica del read-only

La vulnerabilità **[CVE-2026-61788](https://github.com/bytebase/dbhub/security/advisories/GHSA-mwwr-p57h-56pf)** ha interessato il meccanismo di applicazione del read-only di DBHub nelle versioni precedenti a **0.22.6**, consentendo in determinate condizioni scritture indirette tramite query apparentemente di lettura. La correzione comprende l'applicazione della modalità read-only a livello del motore DBMS.

I test svolti sul profilo sperimentale sono coerenti con un comportamento protetto rispetto ai casi provati; **non** costituiscono un test di regressione su tutte le versioni né una verifica generale di assenza di vulnerabilità.

## 10. SQL injection nei custom tool

Il server `dbhub-sqli` espone due custom tool che richiamano funzioni PostgreSQL:

- `search_customer_unsafe`: usa SQL dinamico che concatena direttamente l'input nella query interna;
- `search_customer_safe`: usa una query statica, trattando il parametro ricevuto come dato.

Entrambi i tool passano correttamente un parametro alla funzione SQL sottostante. Tuttavia, nella versione vulnerabile il contenuto viene successivamente concatenato in una **nuova query dinamica**, vanificando la separazione tra dati e sintassi all'interno della funzione.

| Prova | Funzione vulnerabile | Funzione sicura |
|---|---|---|
| Ricerca normale `Lovelace` | 1 record | Ricerca corrispondente prevista |
| Input `x' OR '1'='1` | **4 record** | **0 record** |
| Test UNION-based | Recuperate informazioni sul database e sull'utente di connessione | Non effettuato lo stesso test |

Il test UNION-based sulla funzione vulnerabile ha restituito informazioni su database `pagila`, ruolo `mcp_readonly_pagila` e versione PostgreSQL 18.6. Non è stata dimostrata un'escalation di privilegi né la possibilità di modificare dati attraverso questa SQL injection.

La descrizione completa si trova in [`sql_injection_lab.md`](02_Laboratorio/database/sql_injection_lab.md).

## 11. SQL injection nei tool predefiniti di DBHub

Per approfondire i possibili rischi nei tool predefiniti sono state eseguite prove sul tool `search_objects`, usando `dbhub-readonly-writer`.

| Parametro | Ricerca di controllo | Input contenente sintassi SQL | Risultato |
|---|---|---|---|
| `pattern` | 1 tabella trovata | `mcp_readonly_probe' OR '1'='1` | 0 oggetti |
| `schema` | Schema `security_lab` valido | `security_lab' OR '1'='1` | `SCHEMA_NOT_FOUND` |
| `table` | Colonne `id`, `counter` trovate | `mcp_readonly_probe' OR '1'='1` | 0 colonne |

Non si è osservato alcun ampliamento della ricerca tramite i payload utilizzati. L'esame del percorso di implementazione di DBHub 1.7.1 indica che, per i casi analizzati, il pattern viene impiegato nel filtraggio dei nomi e i valori di schema/tabella sono trattati come dati o validati, anziché interpretati come porzioni di SQL aggiuntivo.

La risposta `SCHEMA_NOT_FOUND` elenca gli schemi disponibili: si tratta di un'esposizione di metadati da considerare separatamente, non di una SQL injection riuscita.

`execute_sql`, invece, è progettato per ricevere un'istruzione SQL completa. L'esecuzione di SQL fornito esplicitamente è una **funzionalità intenzionale**, non di per sé una SQL injection; i rischi dipendono dalle policy applicate e da come l'agente o altri componenti costruiscono le query.

**Limite:** l'assenza di injection osservata nei tre parametri testati non equivale a un'analisi esaustiva di tutte le funzionalità, di tutti gli input o di ogni versione di DBHub.

Per le prove complete e i riferimenti al codice sorgente vedere [`dbhub_security_tests.md`](02_Laboratorio/database/dbhub_security_tests.md).

## 12. Avvio del laboratorio

### 12.1 Prerequisiti

- Docker Desktop e Docker Compose;
- Node.js e npm;
- Claude Desktop, per l'utilizzo dei server MCP;
- accesso locale al repository e ai file di configurazione di esempio.

### 12.2 Inizializzazione di Pagila

Dalla root del repository:

```powershell
git submodule update --init --recursive
cd 02_Laboratorio
Copy-Item .env.example .env.pagila
```

Inserire in `.env.pagila` una password locale sicura, senza versionare il file, quindi avviare PostgreSQL:

```powershell
docker compose --env-file .env.pagila up -d --build
docker compose --env-file .env.pagila ps
```

**Attenzione:** non usare `docker compose down -v` nel normale utilizzo: il comando eliminerebbe anche il volume con i dati del laboratorio.

### 12.3 Preparazione dello schema sperimentale

Prima di eseguire `database/security_lab.sql`, deve esistere il ruolo PostgreSQL `mcp_readonly_pagila` (lo script lo utilizza ma non lo crea). Le istruzioni di configurazione dei ruoli e delle password sono documentate in [`setup.md`](02_Laboratorio/database/setup.md). Le credenziali vanno impostate localmente e mai inserite nei file versionati.

Dalla cartella `02_Laboratorio`:

```powershell
docker cp ".\database\security_lab.sql" tesi-pagila:/tmp/security_lab.sql
docker exec tesi-pagila psql -U postgres -d pagila -v ON_ERROR_STOP=1 -f /tmp/security_lab.sql
```

Per verificare il contatore di prova senza incrementarlo:

```powershell
docker exec tesi-pagila psql -U postgres -d pagila -c "SELECT id, counter FROM security_lab.mcp_readonly_probe;"
```

La creazione delle funzioni `search_customer_safe` e `search_customer_unsafe` e dei rispettivi permessi è descritta nello script [`sql_injection_lab.sql`](02_Laboratorio/database/sql_injection_lab.sql). Seguire la relativa documentazione prima di effettuare i test di SQL injection.

### 12.4 Collegamento di Claude Desktop

I file `dbhub/*.toml.example` devono essere copiati in file `.toml` locali, sostituendo **solo localmente** i segnaposto delle credenziali. Il file di configurazione di Claude Desktop deve fare riferimento ai TOML reali. La procedura completa, incluso l'esempio delle cinque connessioni, è descritta in [`client/claude-desktop.md`](02_Laboratorio/client/claude-desktop.md).

## 13. Documentazione e risultati

| Documento | Contenuto |
|---|---|
| [`01_Ricerca_MCP/confronto.md`](01_Ricerca_MCP/confronto.md) | Confronto tra le implementazioni MCP Server esaminate |
| [`02_Laboratorio/database/setup.md`](02_Laboratorio/database/setup.md) | Setup Pagila, ruoli, privilegi e configurazioni DBHub |
| [`02_Laboratorio/client/claude-desktop.md`](02_Laboratorio/client/claude-desktop.md) | Client MCP e cinque connessioni di laboratorio |
| [`02_Laboratorio/database/sql_injection_lab.md`](02_Laboratorio/database/sql_injection_lab.md) | Test sui custom tool SQL injection sicuro e vulnerabile |
| [`02_Laboratorio/database/dbhub_security_tests.md`](02_Laboratorio/database/dbhub_security_tests.md) | Test read-only, scritture indirette e tool predefiniti DBHub |
| [`02_Laboratorio/database/security_lab.sql`](02_Laboratorio/database/security_lab.sql) | Script dello schema sperimentale e della funzione contatore |

## 14. Conclusioni e limiti

Il laboratorio ha consentito di confrontare **tre profili di autorizzazione PostgreSQL attraverso cinque connessioni DBHub**, verificare separatamente le protezioni del server MCP e del database e confrontare una funzione vulnerabile a SQL injection con una funzione sicura.

Nei casi testati, la modalità read-only di DBHub ha impedito sia modifiche dirette sia una scrittura indiretta tramite funzione PostgreSQL. I payload applicati ai parametri `pattern`, `schema` e `table` di `search_objects` non hanno prodotto SQL injection osservabili.

I risultati sono riferiti al **laboratorio locale e agli input effettivamente provati**: non costituiscono una garanzia di sicurezza generale. Per rafforzare la riproducibilità rimangono utili la registrazione indipendente della versione DBHub effettivamente avviata e la conservazione delle risposte JSON integrali dei test, prive di credenziali.

Questi esperimenti costituiscono una base per il successivo confronto tra differenti implementazioni di MCP Server per database.
