# HenkDz PostgreSQL MCP Server

## 1. Informazioni generali

- **Nome:** HenkDz PostgreSQL MCP Server
- **Repository:** <https://github.com/microsoft/postgres-mcp>
- **Sviluppatore:** Microsoft
- **Package npm:** `@microsoft/postgres-mcp`
- **Licenza:** MIT
- **Tipologia:** MCP Server dedicato a PostgreSQL.

postgres-mcp permette a un agente o client compatibile con MCP di interagire con PostgreSQL per eseguire query, modificare dati, analizzare lo schema, effettuare attività diagnostiche e gestire connessioni.

## 2. Architettura

L'architettura generale può essere rappresentata come:

```text
LLM / AI Agent
       |
       v
  MCP Client
       |
       | MCP
       v
postgres-mcp
       |
       | PostgreSQL
       v
  PostgreSQL
```

Il server funge da gateway tra il client MCP e PostgreSQL.

Uno degli aspetti più importanti per questa tesi è che il server dichiara esplicitamente di essere un gateway e non un policy engine: non decide autonomamente se una tool call sia autorizzata. Le operazioni vengono eseguite con l'identità e i privilegi del ruolo PostgreSQL associato alla connessione.

## 3. Gestione delle connessioni

Il server supporta profili di connessione PostgreSQL.

Un profilo definisce la connessione e il relativo access mode, mentre le credenziali possono essere gestite tramite il keyring del sistema operativo.

Per ambienti headless o containerizzati è possibile utilizzare una connection string tramite:

```text
POSTGRES_MCP_CONNECTION_STRING
```

Le connection string devono essere considerate informazioni sensibili e protette adeguatamente.

## 4. MCP Tools principali

Tra gli strumenti principali sono presenti funzioni per:

- eseguire query PostgreSQL;
- modificare dati;
- gestire e analizzare lo schema;
- elencare e gestire i profili di connessione;
- ottenere informazioni sui database;
- effettuare diagnostica e analisi delle prestazioni;
- importare dati da CSV.

Il server distingue in particolare le operazioni di sola lettura da quelle di modifica.

### Query

`postgres_mcp_query` è destinato alle query di sola lettura.

### Modify

`postgres_mcp_modify` è destinato alle operazioni che possono modificare il database.

Questa separazione è interessante dal punto di vista della sicurezza perché non tutte le operazioni SQL vengono trattate come un'unica categoria indistinta.

## 5. Security model

Il principio di sicurezza principale del progetto è:

```text
MCP Server
    |
    v
PostgreSQL permissions
```

Il server specifica esplicitamente che non autorizza autonomamente le tool call e non può distinguere tra:

- richiesta realmente voluta dall'utente;
- richiesta generata, interpretata erroneamente o indotta da un attacco al modello.

Di conseguenza, tutto ciò che il ruolo PostgreSQL può fare può potenzialmente essere fatto anche dall'agente che utilizza il server.

Per questo i privilegi PostgreSQL rappresentano una barriera di sicurezza fondamentale.

## 6. Read-only

Il server supporta una modalità:

```text
access_mode: ro
```

che impedisce l'utilizzo degli strumenti di scrittura per quella connessione.

Questo controllo deve però essere affiancato ai privilegi del ruolo PostgreSQL.

Il modello consigliato è quindi:

```text
MCP read-only
        +
PostgreSQL read-only role
```

La documentazione considera i privilegi PostgreSQL il confine che deve effettivamente impedire operazioni non autorizzate.

## 7. Least privilege

La documentazione raccomanda esplicitamente di utilizzare ruoli PostgreSQL con il minor numero possibile di privilegi.

Un ambiente di test può quindi prevedere, ad esempio:

- `readonly_user`;
- `writer_user`;
- `admin_user`.

Il server MCP può essere collegato a uno specifico ruolo a seconda dell'attività richiesta.

Questo permette di studiare sperimentalmente come cambiano le capacità dell'agente quando cambiano i privilegi PostgreSQL.

## 8. Autenticazione e autorizzazione

È importante distinguere:

- **Autenticazione:** chi sta effettuando la connessione;
- **Autorizzazione:** quali operazioni può effettuare.

postgres-mcp gestisce le connessioni, ma non si propone come authorization layer completo per le operazioni generate dal modello.

La decisione su ciò che può essere realmente fatto sul database viene affidata principalmente ai privilegi PostgreSQL e ai meccanismi di approvazione e governance del client MCP.

## 9. Aspetti interessanti per la sicurezza

Il modello introduce diverse superfici di rischio.

### Prompt injection

Un attacco può tentare di indurre il modello a generare una tool call diversa da quella desiderata dall'utente.

### Eccessivi privilegi

Se il ruolo PostgreSQL dispone di privilegi elevati, un errore del modello o un attacco può avere conseguenze più estese.

### Tool misuse

Il modello può utilizzare tool validi ma in un contesto non desiderato dall'utente.

### Data leakage

I risultati delle query diventano parte del contesto dell'agente e possono quindi essere elaborati o restituiti dal modello.

### Credential exposure

Le credenziali utilizzate per accedere a PostgreSQL devono essere adeguatamente protette.

## 10. Gestione del filesystem

Gli strumenti relativi ai CSV introducono una superficie di attacco aggiuntiva rispetto al solo database.

L'agente può interagire con file locali attraverso gli strumenti di importazione, quindi i percorsi a cui il server può accedere devono essere controllati.

Questo dimostra che un MCP Server che interagisce con un database può introdurre problemi di sicurezza anche al di fuori del database stesso.

## 11. Audit

La documentazione raccomanda di effettuare logging e auditing anche a livello PostgreSQL.

Questo è importante perché PostgreSQL vede il ruolo utilizzato per la connessione, ma non necessariamente distingue se l'operazione sia stata richiesta direttamente dall'utente oppure generata dal modello tramite MCP.

Un ruolo dedicato agli agenti può quindi essere utile per identificare e tracciare le operazioni provenienti dall'MCP server.

## 12. TLS / SSL

Il server supporta le modalità PostgreSQL relative alla sicurezza delle connessioni e può essere utilizzato con connessioni TLS.

Per ambienti non locali è importante proteggere il traffico tra MCP Server e PostgreSQL.

## 13. Aspetti interessanti per la tesi

Microsoft PostgreSQL MCP Server è particolarmente interessante perché presenta un modello in cui:

```text
LLM
 |
 v
MCP
 |
 v
PostgreSQL role
 |
 v
Database
```

La sicurezza non viene affidata esclusivamente all'MCP Server.

Questo permette di studiare sperimentalmente la differenza tra:

```text
MCP Server + privilegi PostgreSQL
```

e:

```text
MCP Server + authorization layer aggiuntivo
             +
PostgreSQL permissions
```

## 14. Possibile domanda di ricerca

Una possibile domanda derivata dall'analisi è:

> È sufficiente affidare la sicurezza delle operazioni generate da un agente LLM ai privilegi del ruolo PostgreSQL, oppure è necessario introdurre ulteriori controlli a livello MCP?

## 15. Possibili esperimenti

### Esperimento 1 — PostgreSQL roles

Confrontare:

- `readonly_user`;
- `writer_user`;
- `admin_user`.

Verificare quali operazioni l'agente può effettuare.

### Esperimento 2 — read-only

Confrontare:

```text
MCP access_mode = ro
```

con:

```text
MCP write mode
```

e verificare il comportamento delle operazioni di modifica.

### Esperimento 3 — prompt injection / tool misuse

Costruire input che tentino di indurre l'agente a utilizzare strumenti o operazioni diverse da quelle desiderate.

### Esperimento 4 — auditing

Verificare quali informazioni rimangono disponibili nei log PostgreSQL e nei log dell'MCP Server.

## 16. Fonti

### Repository

<https://github.com/microsoft/postgres-mcp>

### Usage

<https://github.com/microsoft/postgres-mcp/blob/main/USAGE.md>

### Microsoft PostgreSQL MCP Server

<https://github.com/microsoft/postgres-mcp>