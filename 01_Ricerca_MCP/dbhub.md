
# DBHub

## 1. Informazioni generali

- **Nome:** DBHub
- **Repository:** <https://github.com/bytebase/dbhub>
- **Sviluppatore:** Bytebase
- **Licenza:** MIT
- **Linguaggio principale:** TypeScript / Node.js
- **Tipologia:** MCP Server per l'accesso a database relazionali tramite Model Context Protocol.

DBHub è un MCP Server progettato come gateway tra client compatibili con MCP e diversi sistemi di gestione di database. Il progetto supporta PostgreSQL, MySQL, MariaDB, SQL Server, Oracle e SQLite.

Il progetto viene descritto come un server MCP minimale e token-efficient, con due strumenti principali disponibili di default e altri strumenti attivabili opzionalmente.



## 2. Architettura

L'architettura generale può essere rappresentata come:

```text
MCP Client
    |
    | MCP
    v
DBHub
    |
    | SQL / Database connection
    v
Database
```

Nel caso studiato nella tesi:

```text
LLM / AI Agent
    |
    v
MCP Client
    |
    | MCP
    v
DBHub
    |
    | SQL
    v
PostgreSQL
```

DBHub svolge quindi il ruolo di intermediario tra il client MCP e il database.

Il client MCP può essere, ad esempio, Claude Desktop, Claude Code, Cursor, VS Code o altri client compatibili.



## 3. Database supportati

DBHub supporta:

- PostgreSQL
- MySQL
- MariaDB
- SQL Server
- Oracle
- SQLite

Nella tesi PostgreSQL sarà utilizzato come principale DBMS per gli esperimenti.



## 4. MCP Tools

DBHub dispone di due tool principali attivati di default:

### `execute_sql`

Permette di eseguire query SQL sul database.

È il tool più importante dal punto di vista della sicurezza perché permette al modello di trasformare una richiesta naturale in un'operazione SQL che viene successivamente eseguita sul database.

**Schema semplificato:**

```text
Utente
|
v
LLM
|
v
MCP Client
|
v
execute_sql
|
v
SQL
|
v
PostgreSQL
```

### `search_objects`

Permette di esplorare la struttura del database, includendo elementi come:

- tabelle
- colonne
- indici
- procedure
- altri oggetti dello schema
- `explain_sql`

### `explain_sql`

Tool opzionale che permette di ottenere il piano di esecuzione di una query senza eseguirla.

### `health_check`

Tool opzionale che permette di ottenere informazioni relative allo stato della connessione e del connection pool.

### Custom Tools

DBHub permette inoltre di definire custom tools tramite configurazione. Questi strumenti possono rappresentare operazioni SQL riutilizzabili e parametrizzate.



## 5. Meccanismi di sicurezza dichiarati

DBHub dichiara diversi meccanismi di sicurezza e controllo:

### Read-only mode

È possibile configurare l'accesso in modalità read-only per impedire operazioni di modifica sul database.

### Row limiting

È possibile limitare il numero massimo di righe restituite da una query.

Questo riduce la possibilità che una singola richiesta restituisca una quantità molto elevata di dati.

### Query timeout

È possibile impostare un timeout per le query, in modo da limitare operazioni che rimangono in esecuzione per periodi eccessivi.

### SSL/TLS

DBHub supporta connessioni cifrate verso i database tramite SSL/TLS.

### SSH tunneling

È supportata anche la connessione ai database tramite tunnel SSH.



## 6. Aspetti di sicurezza interessanti per la tesi

Il principale elemento di interesse è il fatto che DBHub permette a un LLM, tramite il tool execute_sql, di arrivare all'esecuzione di SQL su PostgreSQL.

Questo introduce una superficie di attacco composta almeno dai seguenti elementi:

    ```text
    LLM
    |
    +-- Prompt injection
    |
    v
    MCP Client
    |
    +-- Tool misuse
    |
    v
    DBHub
    |
    +-- SQL validation
    +-- Authorization
    +-- Read-only controls
    |
    v
    PostgreSQL
    |
    +-- Database privileges
    +-- Sensitive data
    +-- System capabilities
    ```

Le principali aree da studiare sono:

- SQL injection
- prompt injection
- tool misuse
- eccesso di privilegi
- privilege escalation
- accesso non autorizzato ai dati
- data leakage
- query pericolose
- uso improprio delle credenziali
- assenza o debolezza dei meccanismi di autenticazione
- esposizione del server MCP sulla rete



## 7. Caso di studio: vulnerabilità del read-only

DBHub ha pubblicato il 24 giugno 2026 una security advisory relativa alle versioni precedenti alla 0.22.6.

La vulnerabilità riguardava il fatto che impostare readonly = true sul tool execute_sql non rendeva effettivamente read-only la connessione PostgreSQL.

La versione vulnerabile si affidava in parte a un classificatore che controllava la prima keyword della query.

Questo approccio poteva essere insufficiente perché una query che iniziava con SELECT poteva comunque provocare effetti collaterali attraverso funzioni PostgreSQL.

L'advisory indica che, in presenza di privilegi sufficienti, questo poteva arrivare a operazioni molto più pericolose, tra cui accesso a file del server e altre operazioni con impatto significativo.

**Versioni interessate:**

`< 0.22.6`

**Versione corretta:**

`0.22.6`

**Fonte:**

<https://github.com/bytebase/dbhub/security/advisories/GHSA-mwwr-p57h-56pf>



## 8. Importanza del caso di studio

Questo problema è particolarmente interessante per la tesi perché mostra un limite del controllo basato esclusivamente sull'analisi della query.

Un semplice schema:

    ```text
    LLM
    |
    v
    DBHub
    |
    v
    SQL classifier
    |
    v
    PostgreSQL
    ```

può non essere sufficiente per garantire la sicurezza.

È possibile invece combinare più livelli di protezione:

    ```text
    LLM
    |
    v
    DBHub
    |
    +-- SQL classification
    |
    +-- Tool restrictions
    |
    +-- Read-only controls
    |
    v
    PostgreSQL
    |
    +-- Database permissions
    +-- Transaction-level restrictions
    ```

Questo approccio è riconducibile al principio di defense in depth.



## 9. Domanda di ricerca preliminare

Una possibile domanda di ricerca derivata dall'analisi di DBHub è:

> È sufficiente analizzare e classificare le query SQL a livello MCP Server per garantire un accesso read-only sicuro a PostgreSQL, oppure è necessario imporre ulteriori vincoli direttamente a livello di database?

Questa domanda potrà essere verificata sperimentalmente nella seconda fase della tesi.



## 10. Possibile esperimento

È possibile realizzare due configurazioni.

### Configurazione A: controllo applicativo

```text
LLM
|
v
MCP Client
|
v
DBHub
|
v
SQL classifier
|
v
PostgreSQL
```

### Configurazione B: controllo applicativo + database

```text
LLM
|
v
MCP Client
|
v
DBHub
|
v
SQL classifier
|
v
PostgreSQL
|
+-- database permissions
+-- read-only transaction / database enforcement
```

Successivamente possono essere eseguite query e richieste progettate per verificare se un'operazione non autorizzata riesce a superare i controlli.

I risultati delle due configurazioni possono essere confrontati.



## 11. Possibili metriche

Durante gli esperimenti si potranno analizzare:

- numero di operazioni autorizzate
- numero di operazioni bloccate
- numero di tentativi riusciti di aggirare i controlli
- tempo di esecuzione
- overhead introdotto dai controlli di sicurezza
- quantità di dati restituiti
- privilegi posseduti dall'utente PostgreSQL
- comportamento in presenza di query particolari



## 12. Collegamento con la tesi

L'analisi di DBHub può essere utilizzata come primo caso di studio per individuare:

```text
MCP Server
    |
    v
Attack Surface
    |
    v
Vulnerabilità
    |
    v
Contromisure
    |
    v
Valutazione sperimentale
```

L'obiettivo non è stabilire se DBHub sia "sicuro" o "insicuro", ma comprendere quali meccanismi di sicurezza vengono utilizzati, quali limiti presentano e come possano essere combinati con i controlli nativi di PostgreSQL.



## 13. Fonti

### Repository ufficiale

<https://github.com/bytebase/dbhub>

### README

<https://github.com/bytebase/dbhub/blob/main/README.md>

### Esempio di configurazione

<https://github.com/bytebase/dbhub/blob/main/dbhub.toml.example>

### Security advisory

<https://github.com/bytebase/dbhub/security/advisories/GHSA-mwwr-p57h-56pf>

### MCP Specification

<https://modelcontextprotocol.io/specification/>