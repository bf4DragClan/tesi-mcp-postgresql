# CrystalDB PostgreSQL MCP Server

## 1. Informazioni generali

- **Nome:** Postgres MCP Pro
- **Repository:** <https://github.com/crystaldba/postgres-mcp>
- **Sviluppatore:** CrystalDB
- **Linguaggio principale:** Python
- **Tipologia:** MCP Server specializzato per PostgreSQL
- **Licenza:** MIT
- **Ultima release ufficiale individuata:** v0.3.0

Postgres MCP Pro è un MCP Server open source progettato per permettere agli agenti AI di interagire con PostgreSQL non soltanto per eseguire query, ma anche per analizzare lo stato del database, studiare i piani di esecuzione e fornire suggerimenti di ottimizzazione.

Il progetto combina quindi due categorie di funzionalità:

- accesso e interrogazione del database;
- analisi e ottimizzazione delle prestazioni PostgreSQL.

Il progetto supporta i trasporti MCP `stdio` e `SSE`.

## 2. Obiettivo del progetto

Il progetto nasce con l'idea di utilizzare un agente AI come assistente per l'intero ciclo di vita di un database PostgreSQL:

```text
sviluppo
   v
test
   v
deployment
   v
performance tuning
   v
manutenzione
```

Tra le funzionalità dichiarate ci sono:

- database health analysis;
- analisi delle query;
- analisi dei piani di esecuzione;
- index tuning;
- generazione SQL basata sullo schema;
- esecuzione SQL con livelli di sicurezza configurabili.

Il progetto non è quindi un semplice wrapper SQL.

## 3. Architettura

L'architettura può essere rappresentata come:

```text
LLM / AI Agent
       |
       v
  MCP Client
       |
       | MCP
       v
Postgres MCP Pro
       |
       +-------------------+
       |                   |
       v                   v
   SQL tools          Performance tools
       |                   |
       +---------+---------+
                 |
                 v
            PostgreSQL
```

Il server utilizza la libreria psycopg3 per la connessione a PostgreSQL.

psycopg3 utilizza libpq, permettendo di utilizzare le funzionalità del protocollo PostgreSQL.

## 4. Installazione e configurazione

Il progetto può essere utilizzato tramite Docker oppure Python.

### Docker

Il repository fornisce un'immagine:

```text
crystaldba/postgres-mcp
```

Esempio:

```powershell
docker pull crystaldba/postgres-mcp
```

### Python

Sono disponibili anche installazioni tramite:

```powershell
pipx install postgres-mcp
```

oppure:

```powershell
uv pip install postgres-mcp
```

### Claude Desktop

Il repository fornisce esempi di configurazione per Claude Desktop.

La configurazione può essere realizzata direttamente tramite il file:

```text
%APPDATA%/Claude/claude_desktop_config.json
```

oppure tramite Docker.

## 5. MCP Tools

Postgres MCP Pro utilizza esclusivamente MCP Tools.

Il progetto specifica esplicitamente di aver scelto i Tools perché sono ampiamente supportati dai client MCP.

A differenza di altri server PostgreSQL, il progetto non usa MCP Resources per esporre le informazioni sullo schema.

## 6. Tools principali

### `list_schemas`

Elenca gli schemi disponibili nell'istanza PostgreSQL.

Può essere utilizzato dall'agente per conoscere la struttura generale del database.

### `list_objects`

Elenca gli oggetti presenti in uno schema.

Può restituire informazioni relative a:

- tabelle;
- viste;
- sequenze;
- estensioni.

### `get_object_details`

Restituisce informazioni dettagliate su un oggetto PostgreSQL.

Per una tabella può fornire informazioni come:

- colonne;
- vincoli;
- indici.

### `execute_sql`

Esegue statement SQL sul database.

Questo è il tool più importante dal punto di vista della sicurezza.

In modalità `unrestricted` permette all'agente di eseguire operazioni di lettura e scrittura.

In modalità `restricted` il tool è limitato alle operazioni read-only.

### `explain_query`

Restituisce il piano di esecuzione di una query.

Può essere utilizzato anche per simulare l'effetto di indici ipotetici.

### `get_top_queries`

Utilizza i dati di `pg_stat_statements` per individuare le query più lente.

### `analyze_workload_indexes`

Analizza il workload del database e suggerisce quali indici potrebbero migliorare le prestazioni.

### `analyze_query_indexes`

Analizza un insieme di query specifiche e suggerisce possibili indici.

### `analyze_db_health`

Esegue diversi controlli sulla salute del database.

Tra gli aspetti analizzati:

- buffer cache;
- connessioni;
- vincoli;
- indici;
- sequenze;
- vacuum.

## 7. Access modes

Uno degli aspetti più interessanti per la tesi è il sistema di controllo degli accessi.

Il progetto supporta almeno due modalità principali:

- `unrestricted`;
- `restricted`.

### Unrestricted

Permette all'agente di utilizzare il database con accesso read/write.

È indicata dal progetto per ambienti di sviluppo dove l'utente accetta una maggiore libertà operativa.

### Restricted

È progettata per ambienti in cui è necessario proteggere il database.

Le operazioni SQL vengono eseguite utilizzando transazioni read-only.

Sono inoltre applicati limiti alle risorse, in particolare al tempo di esecuzione.

Schema:

```text
                    Postgres MCP Pro

                +-------------------+
                | access mode       |
                +-------------------+
                    /          \\
                   /            \\
                  v              v
          unrestricted        restricted
               |                    |
             R/W                read-only
```

## 8. Read-only transaction mode

La modalità `restricted` utilizza transazioni PostgreSQL in sola lettura per evitare modifiche al database.

L'approccio è interessante perché non si limita a dare istruzioni al modello come:

```text
non usare UPDATE o DELETE
```

ma cerca di imporre il comportamento a livello della connessione PostgreSQL.

## 9. Problema del bypass tramite COMMIT e ROLLBACK

Il progetto evidenzia un problema importante.

Un agente potrebbe tentare una sequenza come:

```sql
ROLLBACK;
DROP TABLE users;
```

Se il sistema si limita a impostare una modalità read-only senza impedire il reset della transazione, potrebbe esistere la possibilità di iniziare successivamente una transazione non protetta.

Per questo Postgres MCP Pro analizza il SQL prima dell'esecuzione tramite la libreria `pglast`.

Il parser rifiuta statement che contengono:

- `COMMIT`;
- `ROLLBACK`.

La protezione è quindi composta da:

```text
SQL parsing
+
read-only transaction
```

Questo rappresenta un esempio di defense in depth.

## 10. Limiti delle protezioni read-only

La documentazione specifica anche che il meccanismo non deve essere considerato una barriera assoluta.

Se nel database sono abilitate funzioni/procedure realizzate con linguaggi non sicuri che possono produrre side effect, una query apparentemente read-only potrebbe potenzialmente provocare modifiche.

Quindi anche in modalità `restricted` rimane importante la configurazione e la sicurezza del database PostgreSQL sottostante.

## 11. Connection configuration

Il server utilizza una `DATABASE_URI` per collegarsi a PostgreSQL.

Esempio concettuale:

```text
postgresql://username:password@localhost:5432/database
```

Il progetto stesso segnala che la gestione delle credenziali costituisce un problema di sicurezza.

La documentazione discute infatti diverse possibili modalità di gestione delle connessioni e dei secret.

## 12. Problema delle credenziali passate attraverso MCP

Il progetto evidenzia un rischio interessante.

Se le credenziali del database vengono fornite direttamente attraverso tool MCP, esse possono attraversare il contesto dell'LLM e potenzialmente finire nella cronologia della conversazione.

Questo è un rischio importante perché significa che il secret può uscire dal confine del processo che dovrebbe proteggerlo.

Per questo il progetto preferisce evitare modelli nei quali le credenziali vengono comunicate al server attraverso il modello.

## 13. Analisi delle vulnerabilità attuali

Nel repository GitHub risultano presenti discussioni di sicurezza aperte.

Tra quelle più interessanti:

### Issue #164

È stata segnalata una possibile esposizione derivante dalla modalità predefinita `unrestricted`, nella quale il contenuto SQL ricevuto dall'LLM viene inviato al driver senza una sanitizzazione generale.

La segnalazione parla esplicitamente del rischio che un agente venga indotto tramite prompt injection a eseguire SQL arbitrario.

È importante precisare che questa issue deriva da un'analisi statica e dichiara esplicitamente di non aver verificato un database reale.

### Issue #181

È presente una segnalazione relativa a un possibile bypass della modalità `restricted`/read-only che potrebbe permettere la lettura arbitraria di file lato server tramite una funzione utilizzata nella clausola `FROM`.

Anche in questo caso si tratta di una issue pubblica da considerare come elemento della superficie di sicurezza del progetto, non come una vulnerabilità che possiamo automaticamente considerare confermata.

## 14. Security policy

Il repository GitHub attualmente non presenta un file `SECURITY.md` e GitHub non mostra advisory pubblicate per il progetto.

Questo non significa che il progetto sia insicuro.

Significa solamente che, dal punto di vista della documentazione pubblica del repository, la gestione della sicurezza è descritta soprattutto nella documentazione tecnica e nelle issue/pull request.

## 15. Aspetti interessanti per la tesi

Postgres MCP Pro è particolarmente interessante per tre motivi.

### 1. SQL generato dal modello

L'agente può arrivare a generare ed eseguire SQL.

Quindi il problema non riguarda soltanto il database, ma anche il comportamento probabilistico del modello.

### 2. Read-only multilivello

Il server combina:

```text
SQL parser
+
read-only transaction
+
PostgreSQL
```

Questo è molto utile per studiare la defense in depth.

### 3. Performance tools

Il server permette di accedere a informazioni molto più dettagliate del semplice contenuto delle tabelle:

- query statistics;
- execution plans;
- index information;
- database health.

Questo apre una superficie aggiuntiva relativa alla confidenzialità delle informazioni sul database.

## 16. Possibili superfici di attacco

Le principali aree interessanti sono:

1. SQL injection;
2. prompt injection;
3. arbitrary SQL execution;
4. read-only bypass;
5. accesso a funzioni PostgreSQL con side effects;
6. data leakage;
7. esposizione delle credenziali;
8. eccessivi privilegi PostgreSQL;
9. abuso dei performance tools;
10. esposizione di metadata sul database.

## 17. Possibili esperimenti

### Esperimento 1: access modes

Confrontare:

- `unrestricted`;
- `restricted`.

e verificare quali operazioni vengono consentite.

### Esperimento 2: ruolo PostgreSQL

Confrontare:

- `restricted + mcp_readonly`;
- `restricted + mcp_writer`.

per distinguere il controllo dell'MCP Server da quello del DBMS.

### Esperimento 3: transazioni

Studiare il comportamento di:

```sql
COMMIT;
ROLLBACK;
```

e verificare come il parser e la modalità `restricted` reagiscono.

### Esperimento 4: query apparentemente read-only

Studiare query che iniziano con `SELECT` ma utilizzano funzioni PostgreSQL con effetti collaterali.

### Esperimento 5: performance metadata

Verificare quali informazioni vengono rese disponibili agli agenti tramite:

- `get_top_queries`;
- `analyze_db_health`;
- `explain_query`.

e valutare se tali informazioni possono rappresentare una forma di information disclosure.

## 18. Possibile domanda di ricerca

Una possibile domanda derivata da questo progetto è:

> È possibile garantire un'esecuzione SQL read-only sicura combinando parsing del SQL, transazioni PostgreSQL in sola lettura e privilegi limitati del database?

Una seconda domanda interessante è:

> Quale informazione aggiuntiva sul database viene resa disponibile all'agente tramite gli strumenti di performance analysis e quali rischi di information disclosure introduce?

## 19. Sintesi

Postgres MCP Pro rappresenta un approccio nel quale l'MCP Server cerca di aggiungere direttamente meccanismi di protezione all'esecuzione SQL.

Il modello può essere schematizzato come:

```text
LLM
 |
 v
MCP Client
 |
 v
Postgres MCP Pro
 |
 +-- SQL parsing
 +-- access mode
 +-- read-only transaction
 +-- resource limits
 |
 v
PostgreSQL
 |
 +-- database permissions
```

Per questa ragione è un caso di studio particolarmente utile per confrontare i controlli implementati nell'MCP Server con quelli nativi di PostgreSQL.

## 20. Fonti

- **Repository:** <https://github.com/crystaldba/postgres-mcp>
- **README:** <https://github.com/crystaldba/postgres-mcp/blob/main/README.md>
- **Security / issue tracking:** <https://github.com/crystaldba/postgres-mcp/security>
- **Issue #164:** <https://github.com/crystaldba/postgres-mcp/issues/164>
- **Issue #181:** <https://github.com/crystaldba/postgres-mcp/issues/181>
- **Releases:** <https://github.com/crystaldba/postgres-mcp/releases>