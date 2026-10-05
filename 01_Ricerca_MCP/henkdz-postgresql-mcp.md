# PostgreSQL MCP Server

## 1. Informazioni generali

- **Nome:** PostgreSQL MCP Server
- **Repository:** <https://github.com/HenkDz/postgresql-mcp-server>
- **Package:** `@henkey/postgres-mcp-server`
- **Tipologia:** MCP Server per PostgreSQL con un sistema di policy e modalità di sicurezza integrate.

Il progetto è particolarmente interessante per questa tesi perché presenta esplicitamente un modello di sicurezza multilivello tra MCP e PostgreSQL.

## 2. Architettura

L'architettura può essere rappresentata come:

```text
LLM / AI Agent
       |
       v
  MCP Client
       |
       v
PostgreSQL MCP Server
       |
       +-- Security Policy
       |
       +-- Risk Classification
       |
       +-- Connection Controls
       |
       +-- Filesystem Controls
       |
       v
   PostgreSQL
```

A differenza di un semplice gateway, il server applica una policy prima che le operazioni arrivino al database.

## 3. Security modes

Il progetto utilizza quattro modalità principali.

### `readonly`

È la modalità predefinita.

Permette:

- ispezione dello schema;
- analisi;
- monitoring;
- query in sola lettura.

Non permette le normali operazioni di modifica.

### `write`

Estende la modalità `readonly` permettendo operazioni strutturate di modifica dei dati.

### `admin`

Estende `write` aggiungendo funzionalità amministrative, tra cui:

- DDL;
- gestione dei ruoli;
- Row-Level Security;
- import/export del filesystem;
- operazioni di tipo migration.

### `unsafe`

Permette operazioni più potenti, tra cui SQL arbitrario e raw SQL fragments.

L'utilizzo di operazioni distruttive richiede inoltre:

```text
allowDestructive = true
```

La progressione è quindi:

```text
readonly
   |
   v
write
   |
   v
admin
   |
   v
unsafe
```

## 4. Controllo delle operazioni distruttive

Il parametro:

```text
allowDestructive
```

è `false` per impostazione predefinita.

Questo significa che operazioni considerate distruttive rimangono bloccate finché non viene effettuato un opt-in esplicito.

Tra le operazioni interessate rientrano:

- `DROP`;
- `RESET`;
- SQL arbitrario;
- alcuni raw SQL fragments;
- alcune modifiche ai ruoli e ai privilegi.

Questo principio riduce il rischio di eseguire accidentalmente operazioni irreversibili.

## 5. Tool allow-list

Il parametro:

```text
enabledTools
```

permette di definire esplicitamente quali tool possono essere utilizzati.

Questo è importante perché permette di ridurre la superficie di attacco.

Un deployment può quindi esporre soltanto le funzionalità effettivamente necessarie:

```text
schema inspection
+
read queries
```

invece di rendere disponibile tutto il set di tool.

## 6. Connection strings

Per impostazione predefinita:

```text
allowToolConnectionString = false
```

Il server rifiuta quindi connection string fornite direttamente come argomenti dei tool.

Questo impedisce a un agente di cambiare liberamente il database di destinazione attraverso una semplice tool call.

Quando necessario, è possibile abilitare esplicitamente questa funzionalità.

In quel caso possono essere definite allow-list per le destinazioni autorizzate.

## 7. Connection target allow-list

Quando le connection string dinamiche sono abilitate, il server permette di specificare una lista di destinazioni consentite.

Il pattern può comprendere:

```text
[user@]host[:port][/database]
```

In questo modo è possibile limitare le connessioni a database specifici.

Questo introduce un ulteriore livello di controllo:

```text
LLM
 |
MCP tool
 |
connection target allow-list
 |
PostgreSQL
```

## 8. Arbitrary SQL

Il tool:

```text
pg_execute_sql
```

è classificato come:

```text
arbitrary_sql
```

e non viene considerato un'operazione normalmente sicura.

Per utilizzarlo è necessario utilizzare:

```text
securityMode = unsafe
```

e, per le operazioni distruttive:

```text
allowDestructive = true
```

Questo rappresenta un approccio particolarmente interessante per la tesi: invece di cercare di dimostrare che SQL arbitrario è sempre sicuro, il server lo considera esplicitamente ad alto rischio e lo rende disponibile soltanto con una configurazione più permissiva.

## 9. Parameterized queries

Il server supporta query parametrizzate con placeholder PostgreSQL:

```text
$1
$2
$3
```

e un array separato di valori.

L'utilizzo dei parametri consente di evitare che i valori forniti dall'utente vengano concatenati direttamente nella query SQL e riduce quindi il rischio di SQL injection nei tool che utilizzano questo meccanismo.

Schema:

```text
SQL:
SELECT * FROM users WHERE name = $1

Parameters:
["Mario"]
```

## 10. Row-Level Security

Il server dispone di strumenti dedicati a PostgreSQL Row-Level Security.

Questi permettono di:

- abilitare RLS;
- disabilitare RLS;
- creare policy;
- modificare policy.

Questo è particolarmente interessante perché permette di combinare:

```text
MCP security policy
        +
PostgreSQL Row-Level Security
```

e verificare se l'agente riesce comunque ad accedere a dati appartenenti a utenti diversi.

## 11. Filesystem sandbox

Il server dispone di strumenti per operazioni di import/export.

L'accesso al filesystem non è libero: i percorsi devono rientrare nel workspace configurato.

Il workspace può essere definito tramite:

```text
POSTGRES_MCP_WORKSPACE_DIR
```

o tramite parametro di avvio equivalente.

Sono inoltre applicati limiti sulla dimensione dei file.

Questo crea una separazione tra:

```text
Database security
```

e:

```text
Filesystem security
```

## 12. Docker security

L'immagine Docker del progetto utilizza un utente non-root chiamato:

```text
node
```

e una build multi-stage.

L'esecuzione con un utente non privilegiato riduce il rischio nel caso in cui il processo venga compromesso.

L'isolamento effettivo rimane comunque affidato al runtime Docker e alla configurazione dell'ambiente di deployment.

## 13. Audit e logging

Quando una richiesta viene bloccata dai controlli di sicurezza viene generato un evento strutturato con prefisso:

```text
[MCP Audit]
```

L'evento può contenere informazioni come:

- motivazione del rifiuto;
- nome del tool;
- security mode;
- stato di `allowDestructive`;
- presenza di connection string specifiche;
- categoria di rischio.

Per evitare di trasformare il logging in una nuova fonte di esposizione di dati, l'audit non registra normalmente:

- SQL completo;
- password;
- payload completo della richiesta.

Gli eventi possono essere salvati in un file JSONL tramite la configurazione di audit del server.

## 14. Query debugging

Esiste una modalità di debug:

```text
POSTGRES_MCP_DEBUG_SQL=true
```

che abilita logging SQL più dettagliato.

Questa funzione deve essere utilizzata con cautela perché può registrare SQL e bind values.

È quindi indicata per ambienti di test e debugging controllati, non come configurazione standard di produzione.

## 15. Timeouts e resource limits

Il server dispone di diversi timeout configurabili, tra cui:

- connection timeout;
- statement timeout;
- query timeout;
- lock timeout;
- idle-in-transaction timeout.

Sono inoltre presenti limiti sul numero massimo di connessioni del pool.

Questi controlli aiutano a ridurre il rischio derivante da query o transazioni che rimangono attive troppo a lungo.

## 16. Least privilege

Il progetto sottolinea che l'MCP Server non sostituisce i privilegi PostgreSQL.

La connessione dovrebbe utilizzare un ruolo con privilegi minimi.

Sono disponibili template differenti per ruoli:

- `readonly`;
- `writer`;
- `schema-admin`;
- `role-admin`.

Questo permette di allineare:

```text
MCP securityMode
```

e:

```text
PostgreSQL privileges
```

Ad esempio:

```text
readonly MCP
      +
readonly PostgreSQL role
```

oppure:

```text
write MCP
      +
writer PostgreSQL role
```

## 17. Principio di defense in depth

Il progetto utilizza diversi livelli indipendenti:

```text
PostgreSQL permissions
          +
MCP security policy
          +
Tool allow-list
          +
Connection target restrictions
          +
Filesystem restrictions
          +
Timeouts
          +
Audit
```

Questo rappresenta un esempio concreto di defense in depth.

Il server stesso specifica comunque che non è un database firewall e non sostituisce i privilegi PostgreSQL.

## 18. Aspetti interessanti per la tesi

HenkDz è particolarmente utile come caso di studio perché rappresenta un approccio in cui l'MCP Server non è solamente un gateway.

È possibile rappresentarlo come:

```text
LLM
 |
 v
MCP Client
 |
 v
MCP Server
 |
 +-- Security mode
 +-- Tool policy
 +-- Risk classification
 +-- Destructive checks
 +-- Connection restrictions
 +-- Filesystem restrictions
 |
 v
PostgreSQL
 |
 +-- Database permissions
 +-- Row-Level Security
```

Questo permette di confrontare un MCP Server con una policy di sicurezza integrata con un MCP Server che delega maggiormente la sicurezza al DBMS.

## 19. Possibile domanda di ricerca

Una possibile domanda derivata dall'analisi è:

> Quanto aumenta la sicurezza dell'accesso a PostgreSQL quando un MCP Server applica una policy di sicurezza prima dell'esecuzione delle operazioni, rispetto al solo utilizzo dei privilegi PostgreSQL?

## 20. Possibili esperimenti

### Esperimento 1 — Security modes

Confrontare:

- `readonly`;
- `write`;
- `admin`;
- `unsafe`.

Verificare quali operazioni diventano disponibili.

### Esperimento 2 — Destructive operations

Confrontare:

```text
allowDestructive = false
```

con:

```text
allowDestructive = true
```

e verificare quali operazioni vengono bloccate.

### Esperimento 3 — Connection targets

Verificare il comportamento con:

```text
allowToolConnectionString = false
```

e successivamente con la funzionalità abilitata e una allow-list.

### Esperimento 4 — Parameterized queries

Confrontare query parametrizzate e query che permettono input SQL non strutturato.

### Esperimento 5 — Row-Level Security

Creare più utenti PostgreSQL con accesso differente ai dati e verificare se l'MCP Server riesce a rispettare i limiti imposti da PostgreSQL.

## 21. Fonti

### Repository

<https://github.com/HenkDz/postgresql-mcp-server>

### Security

<https://github.com/HenkDz/postgresql-mcp-server/blob/main/SECURITY.md>

### Tool schemas

<https://github.com/HenkDz/postgresql-mcp-server/blob/main/TOOL_SCHEMAS.md>

### README

<https://github.com/HenkDz/postgresql-mcp-server/blob/main/README.md>