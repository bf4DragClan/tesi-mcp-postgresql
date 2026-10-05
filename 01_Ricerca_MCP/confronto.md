# Confronto tra MCP Server per PostgreSQL

## 1. Obiettivo

Questa analisi confronta tre MCP Server che permettono a un agente o client compatibile con Model Context Protocol (MCP) di interagire con PostgreSQL:

- DBHub;
- Microsoft PostgreSQL MCP Server;
- HenkDz PostgreSQL MCP Server.

L'obiettivo non è stabilire quale progetto sia "più sicuro", ma individuare i diversi approcci utilizzati per controllare l'accesso a PostgreSQL attraverso un agente LLM e identificare le principali superfici di attacco e i meccanismi di mitigazione.

## 2. Confronto generale

Le caratteristiche sono suddivise in tre tabelle tematiche.

### Caratteristiche generali

| Caratteristica | DBHub | Microsoft postgres-mcp | HenkDz |
|---|---|---|---|
| Database principale | PostgreSQL | PostgreSQL | PostgreSQL |
| Altri DB supportati | Sì | No | No |
| Approccio | Gateway MCP per database | Gateway MCP con gestione delle connessioni | Server MCP con policy esplicita |
| Read-only | Sì | Sì | Sì |
| Scrittura | Se configurata | Write tools/profilo appropriato | Security mode appropriato |
| Query SQL | `execute_sql` | `postgres_mcp_query` / `postgres_mcp_modify` | Tool specifici, incluso `pg_execute_sql` |

### Sicurezza e autorizzazione

| Caratteristica | DBHub | Microsoft postgres-mcp | HenkDz |
|---|---|---|---|
| Controlli a livello MCP | Sì | Limitati: non è un policy engine | Sì, numerosi |
| Privilegi PostgreSQL | Fondamentali | Fondamentali | Fondamentali |
| Least privilege | Raccomandato | Centrale | Centrale |
| Tool allow-list | Possibile tramite configurazione | Da approfondire | Sì |
| Row limiting | Sì | Da approfondire | Da approfondire |
| Modalità di sicurezza | Limitate | `access_mode` | `readonly`, `write`, `admin`, `unsafe` |
| Operazioni distruttive | Configurazione/read-only | Tool e privilegi PostgreSQL | `allowDestructive=true` |
| SQL arbitrario | Da analizzare | Da analizzare | `arbitrary_sql` con `unsafe` |

### Connessioni e gestione operativa

| Caratteristica | DBHub | Microsoft postgres-mcp | HenkDz |
|---|---|---|---|
| Query timeout | Sì | PostgreSQL/configurazione | Sì |
| Gestione connessioni | DSN/TOML e altre modalità | Profili di connessione | Connection string e restrizioni sulle destinazioni |
| Gestione credenziali | Configurazione, ambiente o keyring | Keyring del sistema operativo / altre modalità | Configurazione a runtime |
| Controllo filesystem | Limitato/non centrale | Sì, per gli strumenti CSV | Sì, tramite workspace |
| Audit | Da approfondire sperimentalmente | PostgreSQL/logging | Audit MCP integrato |

## 3. DBHub

### Approccio

DBHub è un MCP Server general-purpose che funziona come gateway tra client MCP e diversi DBMS.

Di default espone principalmente:

- `execute_sql`;
- `search_objects`.

Sono disponibili anche strumenti opzionali come:

- `explain_sql`;
- `health_check`;
- custom tools.

### Meccanismi di sicurezza rilevanti

DBHub mette a disposizione:

- modalità read-only;
- limite al numero massimo di righe restituite;
- timeout delle query;
- SSL/TLS;
- possibilità di utilizzare SSH tunnel;
- configurazione tramite TOML.

Un aspetto importante è la possibilità di combinare il controllo applicativo con vincoli direttamente a livello database.

### Interesse per la tesi

DBHub rappresenta un esempio di MCP Server relativamente minimale nel quale è particolarmente interessante analizzare il rapporto tra:

```text
MCP Server
     +
query validation
     +
PostgreSQL
```

Un caso di studio particolarmente interessante riguarda la protezione read-only e il modo in cui questa viene combinata con l'enforcement del database.

## 4. Microsoft PostgreSQL MCP Server

### Approccio

Microsoft postgres-mcp è focalizzato su PostgreSQL e include funzionalità relative a:

- gestione delle connessioni;
- query;
- modifica dei dati;
- analisi dello schema;
- diagnostica;
- importazione di dati.

Tra i tool principali sono presenti:

- `postgres_mcp_query`;
- `postgres_mcp_modify`;
- strumenti di gestione delle connessioni;
- strumenti per lo schema;
- strumenti per CSV e diagnostica.

### Modello di sicurezza

La documentazione dichiara esplicitamente che il server è un:

```text
gateway, non un policy engine
```

Il server esegue le operazioni utilizzando l'identità e i privilegi del ruolo PostgreSQL associato alla connessione.

Di conseguenza:

```text
MCP Server
     |
     v
PostgreSQL Role
     |
     v
PostgreSQL
```

Il ruolo PostgreSQL costituisce una delle principali barriere di sicurezza.

### Read-only

Il server permette di impostare un profilo con:

```text
access_mode = ro
```

ma la documentazione raccomanda di utilizzare contemporaneamente un ruolo PostgreSQL realmente read-only.

Quindi:

```text
MCP read-only
        +
PostgreSQL read-only role
```

rappresentano due livelli distinti di protezione.

### Interesse per la tesi

Questo progetto rappresenta un modello nel quale la sicurezza viene fortemente delegata al DBMS.

È quindi particolarmente utile per studiare la domanda:

> Quanto è sufficiente utilizzare i privilegi PostgreSQL come principale confine di sicurezza per un agente LLM?

## 5. HenkDz PostgreSQL MCP Server

### Approccio

HenkDz introduce un livello di policy più esplicito tra MCP e PostgreSQL.

Il server utilizza quattro modalità principali:

- `readonly`;
- `write`;
- `admin`;
- `unsafe`.

Le funzionalità disponibili aumentano progressivamente con il livello di sicurezza.

### `readonly`

Permette:

- ispezione;
- analisi;
- monitoring;
- query read-only.

### `write`

Aggiunge operazioni strutturate di modifica dei dati.

### `admin`

Aggiunge:

- DDL;
- gestione dei ruoli;
- Row-Level Security;
- import/export;
- migration-style operations.

### `unsafe`

Permette operazioni ad alto rischio, tra cui SQL arbitrario e raw SQL fragments.

Le operazioni distruttive richiedono inoltre:

```text
allowDestructive = true
```

### Altri controlli

Il server implementa anche:

- `enabledTools` per limitare i tool disponibili;
- restrizioni sulle connection string;
- allow-list delle destinazioni di connessione;
- sandbox del filesystem;
- audit degli eventi di sicurezza;
- timeout;
- query parametrizzate;
- supporto a Row-Level Security;
- esecuzione Docker come utente non-root.

### Interesse per la tesi

HenkDz rappresenta un modello in cui l'MCP Server può essere utilizzato come vero e proprio punto di enforcement delle policy.

L'architettura può essere schematizzata come:

```text
LLM
 |
 v
MCP Client
 |
 v
Security Policy
 |
 +-- security mode
 +-- tool restrictions
 +-- destructive checks
 +-- connection restrictions
 +-- filesystem restrictions
 |
 v
PostgreSQL
 |
 +-- database permissions
 +-- Row-Level Security
```

Questo permette di studiare il rapporto tra sicurezza implementata nell'MCP Server e sicurezza nativa PostgreSQL.

## 6. Differenze principali

Dall'analisi preliminare emergono tre approcci differenti.

### DBHub

L'attenzione è rivolta principalmente a fornire un'interfaccia semplice e controllata verso i database.

```text
MCP
 |
 v
DBHub
 |
 +-- guardrails
 |
 v
PostgreSQL
```

### Microsoft postgres-mcp

Il server enfatizza il principio secondo cui i privilegi reali devono essere imposti da PostgreSQL.

```text
MCP
 |
 v
postgres-mcp
 |
 v
PostgreSQL role
 |
 v
PostgreSQL
```

### HenkDz

Il server introduce una policy esplicita tra MCP e database.

```text
MCP
 |
 v
Security Policy
 |
 v
PostgreSQL role
 |
 v
PostgreSQL
```

## 7. Prime superfici di attacco individuate

Dall'analisi dei tre progetti emergono diverse aree che possono essere studiate sperimentalmente:

- eccessivi privilegi del ruolo PostgreSQL;
- prompt injection;
- tool misuse;
- SQL injection;
- esecuzione di SQL arbitrario;
- operazioni distruttive;
- accesso non autorizzato ai dati;
- data leakage;
- uso di connection string non autorizzate;
- accesso non controllato al filesystem;
- query troppo pesanti o non terminate;
- mancanza di auditing sufficiente;
- differenze tra controlli applicati dall'MCP Server e controlli applicati direttamente da PostgreSQL.

## 8. Prime domande di ricerca

L'analisi preliminare permette di formulare alcune domande che potranno essere verificate durante la fase sperimentale.

### Domanda 1

> È sufficiente il controllo delle query a livello MCP Server per garantire un accesso sicuro a PostgreSQL?

### Domanda 2

> Quanto incidono i privilegi del ruolo PostgreSQL sulla sicurezza complessiva dell'agente?

### Domanda 3

> Quanto può ridurre la superficie di attacco un MCP Server che implementa policy esplicite sui tool?

### Domanda 4

> È possibile combinare efficacemente:

> ```text
> MCP security policy
>         +
> PostgreSQL permissions
>         +
> Row-Level Security
> ```

> per limitare il comportamento di un agente LLM?

### Domanda 5

Qual è il compromesso tra sicurezza e funzionalità quando si passa da un accesso read-only a modalità che permettono scrittura o SQL arbitrario?

## 9. Possibile modello sperimentale

Una possibile struttura per gli esperimenti futuri è:

```text
LLM
 |
 v
MCP Client
 |
 v
MCP Server
 |
 v
Security Layer
 |
 v
PostgreSQL
```

Saranno confrontate configurazioni differenti, ad esempio:

- **A.** MCP senza restrizioni significative;
- **B.** MCP read-only;
- **C.** MCP + PostgreSQL least privilege;
- **D.** MCP policy + PostgreSQL least privilege;
- **E.** MCP policy + PostgreSQL least privilege + RLS.

Per ogni configurazione potranno essere testate richieste legittime e richieste progettate per tentare di superare i limiti imposti.

## 10. Conclusione preliminare

I tre progetti mostrano che la sicurezza di un MCP Server collegato a PostgreSQL può essere affrontata a livelli differenti.

Il problema non riguarda quindi esclusivamente la sicurezza del database e non riguarda esclusivamente la sicurezza dell'MCP Server.

Una possibile rappresentazione del problema complessivo è:

```text
        LLM / Agent
             |
             v
         MCP Client
             |
             v
         MCP Server
             |
      Security Layer
             |
             v
      PostgreSQL Role
             |
             v
         PostgreSQL
```

La fase successiva della ricerca consiste nel costruire un ambiente sperimentale controllato e verificare concretamente come questi diversi livelli influenzino le operazioni che un agente può eseguire.

## 11. Fonti principali

### DBHub

- <https://github.com/bytebase/dbhub>
- <https://github.com/bytebase/dbhub/blob/main/README.md>
- <https://github.com/bytebase/dbhub/blob/main/dbhub.toml.example>

### Microsoft PostgreSQL MCP

- <https://github.com/microsoft/postgres-mcp>
- <https://github.com/microsoft/postgres-mcp/blob/main/USAGE.md>

### HenkDz PostgreSQL MCP Server

- <https://github.com/HenkDz/postgresql-mcp-server>
- <https://github.com/HenkDz/postgresql-mcp-server/blob/main/SECURITY.md>
- <https://github.com/HenkDz/postgresql-mcp-server/blob/main/TOOL_SCHEMAS.md>

### MCP

- <https://modelcontextprotocol.io/>