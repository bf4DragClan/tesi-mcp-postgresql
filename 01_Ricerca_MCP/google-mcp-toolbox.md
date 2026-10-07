# Google MCP Toolbox for Databases

## 1. Informazioni generali

- **Nome:** MCP Toolbox for Databases
- **Repository:** <https://github.com/googleapis/mcp-toolbox>
- **Sviluppatore:** Google
- **Linguaggio principale:** Go
- **Licenza:** Apache 2.0
- **Tipologia:** MCP Server e framework per la creazione di tool per database.

MCP Toolbox for Databases è un progetto open source che permette agli agenti AI di interagire con database attraverso MCP.

Il progetto ha due utilizzi principali:

1. fornire tool per database già pronti all'uso;
2. permettere di creare tool personalizzati con logica e query definite dallo sviluppatore.

Il progetto supporta numerosi database, tra cui PostgreSQL, MySQL, SQL Server, Oracle, MongoDB, Redis, BigQuery e Spanner.


## 2. Architettura

L'architettura generale può essere rappresentata come:

```text
LLM / AI Agent
    |
    v
MCP Client
    |
    v
MCP Toolbox
    |
    +------------------+
    |                  |
    v                  v
Prebuilt Tools     Custom Tools
    |                  |
    +--------+---------+
             |
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
    v
MCP Toolbox
    |
    v
PostgreSQL
```

Toolbox svolge quindi il ruolo di intermediario tra il client MCP e il database.


## 3. Database supportati

MCP Toolbox supporta diversi sistemi di database e servizi, tra cui:

- PostgreSQL
- MySQL
- SQL Server
- Oracle
- MongoDB
- Redis
- BigQuery
- Spanner

In questa analisi PostgreSQL è il DBMS di riferimento.


## 4. Configurazione di PostgreSQL

La configurazione delle sorgenti e dei tool può essere definita in un file `tools.yaml`.

Una sorgente PostgreSQL può contenere le informazioni necessarie alla connessione, ad esempio:

```yaml
kind: source
name: my-pg-source
type: postgres
host: 127.0.0.1
port: 5432
database: toolbox_db
user: toolbox_user
password: my-password
```

Le credenziali devono essere trattate come informazioni sensibili e non devono essere esposte all'LLM.


## 5. Tool predefiniti

Toolbox mette a disposizione tool per interagire con PostgreSQL. Tra quelli di interesse per questa analisi:

- `execute_sql`
- `list_tables`
- `list_schemas`
- `list_roles`
- `list_active_queries`
- `list_locks`
- `list_indexes`
- `list_sequences`
- `list_triggers`
- `list_extensions`
- `database_overview`
- strumenti per statistiche e diagnostica

Questi strumenti permettono all'agente di interrogare i dati e di ottenere informazioni sulla struttura e sul funzionamento del database.


## 6. Tool `execute_sql`

Il tool `execute_sql` permette di eseguire SQL sul database. È particolarmente rilevante per la sicurezza perché rappresenta un accesso generico alle funzionalità SQL.

Schema semplificato:

```text
LLM
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

Maggiore è la libertà concessa al tool, maggiore può essere la superficie di attacco. I privilegi effettivi dipendono anche dall'utente PostgreSQL utilizzato per la connessione.


## 7. Custom tools

Una delle caratteristiche principali di Toolbox è la possibilità di definire strumenti personalizzati tramite `tools.yaml`.

Esempio di tool che cerca un cliente per nome:

```yaml
kind: tool
name: search_customer
type: postgres-sql
source: my-pg-source
description: Search for a customer by name.
parameters:
  - name: name
    type: string
    description: Customer name
statement: |
  SELECT *
  FROM customers
  WHERE name ILIKE '%' || $1 || '%';
```

In questo caso la query è definita dallo sviluppatore e il modello fornisce il parametro `name`.

### Confronto tra SQL generico e custom tool

Con SQL generico il modello può scegliere quale query eseguire:

```text
LLM
    |
    v
execute_sql
    |
    v
SQL arbitrario
    |
    v
PostgreSQL
```

Con un custom tool, invece, il modello invoca una funzionalità specifica e fornisce i parametri previsti:

```text
LLM
    |
    v
search_customer
    |
    v
Parametro
    |
    v
Query predefinita
    |
    v
PostgreSQL
```

Limitare ciò che il modello può chiedere al database, definendo tool specifici invece di esporre SQL arbitrario, può ridurre la superficie di attacco.


## 8. Parametri e query parametrizzate

I custom tools possono separare i parametri dalla query SQL.

Esempio:

```sql
SELECT *
FROM customers
WHERE city = $1;
```

Il parametro può essere fornito separatamente:

```json
["Milano"]
```

La separazione tra query e parametri riduce il rischio di SQL injection rispetto alla costruzione della query tramite concatenazione di stringhe.


## 9. Toolsets

Toolbox permette di raggruppare i tool in `toolsets`. In questo modo si possono creare gruppi differenti in base all'agente o all'applicazione che deve utilizzarli.

Esempio:

```text
readonly_toolset
    |
    +-- list_tables
    +-- search_customer
    +-- database_overview
```

Esporre a un agente solo i tool necessari permette di ridurre le funzionalità disponibili e la relativa superficie di attacco.


## 10. Autenticazione e autorizzazione

Toolbox supporta meccanismi di autenticazione e autorizzazione per le connessioni MCP. La documentazione include:

- OAuth
- OpenID Connect
- token Bearer
- scope a livello di tool

Le versioni recenti hanno inoltre rafforzato la validazione degli scope dei tool e la separazione dei meccanismi di verifica OAuth. (<https://github.com/googleapis/mcp-toolbox>)

Questi meccanismi permettono di inserire un livello di controllo tra il client MCP e Toolbox:

```text
MCP Client
    |
    v
Autenticazione e autorizzazione
    |
    v
MCP Toolbox
```


## 11. Controlli read-only

Toolbox supporta meccanismi per limitare l'accesso alle operazioni di sola lettura. La documentazione descrive una strategia di defense in depth che può coinvolgere:

1. controlli a livello di database o protocollo;
2. esclusione dei tool che consentono modifiche;
3. annotazioni MCP.

Un tool può essere annotato come read-only, ad esempio:

```json
{
  "annotations": {
    "readOnlyHint": true
  }
}
```

Le annotazioni informano il client del comportamento previsto del tool; il controllo effettivo deve essere garantito anche dai livelli sottostanti.


## 12. Parametri sensibili

Toolbox permette di contrassegnare come sensibili i parametri di un tool, ad esempio:

```yaml
secure: true
```

Questo meccanismo è pensato per evitare che dati riservati debbano essere gestiti direttamente nel contesto dell'LLM. Può essere utile per proteggere:

- credenziali
- token
- altri segreti


## 13. Information disclosure

Toolbox espone anche strumenti diagnostici che possono fornire informazioni dettagliate sul database, ad esempio:

- `list_roles`
- `list_active_queries`
- `list_pg_settings`
- `database_overview`
- `list_locks`

Questi strumenti possono rivelare informazioni sull'infrastruttura oltre ai dati contenuti nelle tabelle. È quindi utile distinguere tra:

```text
Accesso ai dati
        +
Accesso ai metadati
```


## 14. Superficie di attacco

Le principali aree di interesse per la tesi sono:

- SQL injection
- esecuzione di SQL arbitrario
- prompt injection
- uso improprio dei tool
- esposizione eccessiva dei tool
- privilegi PostgreSQL eccessivi
- data leakage
- divulgazione di metadati
- esposizione delle credenziali
- problemi di autenticazione e autorizzazione
- sicurezza del trasporto HTTP


## 15. Interesse per la tesi

MCP Toolbox è particolarmente interessante perché permette di confrontare due modelli di accesso al database:

### Modello A: SQL generico

```text
LLM
    |
    v
execute_sql
    |
    v
PostgreSQL
```

### Modello B: custom tool

```text
LLM
    |
    v
Custom tool
    |
    v
Parametri controllati
    |
    v
Query predefinita
    |
    v
PostgreSQL
```

Il confronto permette di studiare se la progettazione dei tool possa essere utilizzata come meccanismo di sicurezza.


## 16. Possibili esperimenti

### Esperimento 1: `execute_sql` e custom tool

Confrontare la superficie di attacco di SQL arbitrario con quella di un tool basato su una query parametrizzata.

### Esperimento 2: toolsets

Creare gruppi differenti di strumenti e verificare quali funzionalità risultano effettivamente disponibili all'agente.

### Esperimento 3: privilegi PostgreSQL

Confrontare ruoli PostgreSQL con privilegi differenti, ad esempio:

- `mcp_readonly`
- `mcp_writer`

### Esperimento 4: esposizione dei metadati

Studiare quali informazioni vengono esposte agli agenti attraverso gli strumenti diagnostici e verificare l'effetto della loro disponibilità.


## 17. Possibili domande di ricerca

- È più sicuro esporre SQL arbitrario oppure un insieme limitato di custom tools basati su query parametrizzate?
- Quanto riduce la superficie di attacco la limitazione dei tool disponibili all'agente?
- Quali informazioni sull'infrastruttura PostgreSQL vengono esposte agli agenti attraverso i tool diagnostici?


## 18. Sintesi

MCP Toolbox rappresenta un approccio nel quale l'MCP Server può essere utilizzato non solo come gateway, ma anche come livello di progettazione e controllo dei tool.

```text
LLM
    |
    v
MCP Client
    |
    v
MCP Toolbox
    |
    +-- Autenticazione
    +-- Autorizzazione
    +-- Toolsets
    +-- Validazione dei parametri
    +-- Custom tools
    |
    v
PostgreSQL
    |
    +-- Ruoli e privilegi
    +-- Controlli nativi di sicurezza
```

Per la tesi è particolarmente utile per studiare il rapporto tra progettazione dei tool, sicurezza MCP e privilegi del database.


## 19. Fonti

- **Repository:** <https://github.com/googleapis/mcp-toolbox>
- **Documentazione:** <https://googleapis.github.io/mcp-toolbox/>
- **Tool configuration:** <https://github.com/googleapis/mcp-toolbox/blob/main/README.md>
- **Changelog:** <https://github.com/googleapis/mcp-toolbox/blob/main/CHANGELOG.md>
