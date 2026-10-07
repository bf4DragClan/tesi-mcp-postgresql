# Confronto tra MCP Server per PostgreSQL

## 1. Obiettivo

Questa analisi confronta quattro MCP Server/framework utilizzabili per permettere ad agenti LLM di interagire con database PostgreSQL:

- DBHub
- HenkDz PostgreSQL MCP Server
- CrystalDB Postgres MCP Pro
- Google MCP Toolbox for Databases

L'obiettivo non è stabilire quale progetto sia "più sicuro", ma individuare i diversi approcci utilizzati per controllare l'interazione tra agente LLM, MCP Server e database PostgreSQL.

Il confronto serve inoltre a individuare le principali superfici di attacco e i meccanismi di sicurezza che potranno essere analizzati nella successiva fase sperimentale.

---

## 2. Confronto generale

| Caratteristica | DBHub | HenkDz PostgreSQL MCP Server | CrystalDB Postgres MCP Pro | Google MCP Toolbox |
|---|---|---|---|---|
| Focus principale | Gateway database | Sicurezza e policy MCP | PostgreSQL + performance | Framework per database tools |
| PostgreSQL | ✅ | ✅ | ✅ | ✅ |
| Multi-database | ✅ | ❌ | ❌ | ✅ |
| Modalità Read-only | ✅ | ✅ | ✅ | ✅ |
| Write | ✅ configurabile | ✅ `write` | ✅ `unrestricted` | ✅ tramite tool/configurazione |
| SQL arbitrario | `execute_sql` con guardrail | Solo `unsafe` | Disponibile in unrestricted | Disponibile tramite tool SQL |
| Policy a livello MCP | Limitata | ✅ molto forte | ✅ access mode | ✅ toolsets / authorization |
| Privilegi PostgreSQL | Fondamentali | Fondamentali | Fondamentali | Fondamentali |
| Tool allow-list | Configurabile | ✅ `enabledTools` | Limitata | ✅ toolsets |
| Query parametrizzate | ✅ custom tools | ✅ | ✅ | ✅ custom tools |
| Gestione credenziali | Configurazione/ambiente | Connection string / runtime | DATABASE_URI | Configurazione / secret management |
| Performance analysis | Limitata | ✅ diagnostica | ✅ molto importante | ✅ diagnostica |
| Filesystem access | Limitato | ✅ con workspace | Limitato | Dipendente dai tool |
| Authentication MCP | Limitata | Dipende dal client | Limitata | ✅ OAuth/OIDC |
| Authorization MCP | Limitata | Policy server-side | Limitata | ✅ scope / authorization |
| Audit | Disponibile | ✅ MCP Audit | Limitato | Logging/toolbox |
| Trasporto HTTP | ✅ | ✅/configurabile | ✅ SSE | ✅ |
| Complessità | Bassa | Media/alta | Media | Alta |

---

## 3. DBHub

### Approccio

DBHub è un MCP Server minimale e general-purpose che agisce come gateway tra client MCP e database.

Supporta PostgreSQL e diversi altri DBMS.

Di default espone solamente due tool:

- `execute_sql`
- `search_objects`

con strumenti aggiuntivi attivabili opzionalmente.

### Sicurezza

DBHub introduce diversi guardrail:

- modalità read-only;
- limite al numero di righe;
- query timeout;
- SSL/TLS;
- SSH tunneling;
- custom tools parametrizzati.

L'approccio è quindi quello di mantenere il server relativamente semplice e aggiungere controlli specifici attorno all'esecuzione SQL.

### Interesse per la tesi

DBHub rappresenta una buona baseline perché permette di studiare il caso:

```text
LLM
 ↓
MCP Server
 ↓
execute_sql
 ↓
PostgreSQL
```

È particolarmente interessante per analizzare il rapporto tra controlli implementati dall'MCP Server e privilegi PostgreSQL.

## 4. HenkDz PostgreSQL MCP Server

### Approccio

HenkDz adotta un approccio più orientato alla sicurezza rispetto a un semplice gateway.

Il server classifica le operazioni e applica una policy prima che la richiesta raggiunga PostgreSQL.

Sono disponibili quattro modalità:

```text
readonly
write
admin
unsafe
```

### Sicurezza

La modalità predefinita è readonly.

L'aumento dei privilegi è esplicito:

```text
readonly
   ↓
write
   ↓
admin
   ↓
unsafe
```

Sono inoltre presenti:

- `allowDestructive`;
- allow-list dei tool tramite `enabledTools`;
- restrizioni sulle connection string;
- allow-list delle destinazioni;
- sandbox del filesystem;
- audit degli eventi;
- timeout;
- query parametrizzate;
- supporto PostgreSQL Row-Level Security.

Le operazioni distruttive e l'SQL arbitrario richiedono configurazioni esplicite più permissive.

### Interesse per la tesi

È un caso particolarmente interessante per studiare l'MCP Server come vero e proprio punto di enforcement delle policy.

Architettura:

```text
LLM
 ↓
MCP Client
 ↓
Security Policy
 ↓
PostgreSQL
```

Permette quindi di confrontare la sicurezza applicata dall'MCP con quella nativa del database.

## 5. CrystalDB Postgres MCP Pro

### Approccio

Postgres MCP Pro è un MCP Server specificamente progettato per PostgreSQL.

Oltre alle normali operazioni SQL, integra numerosi strumenti dedicati all'analisi delle performance e dello stato del database.

Tra le funzionalità disponibili troviamo:

- esecuzione SQL;
- analisi dei piani di esecuzione;
- analisi dello stato del database;
- analisi del workload;
- suggerimenti sugli indici;
- statistiche sulle query.

### Access modes

Il progetto distingue due modalità principali:

```text
unrestricted
restricted
```

- `unrestricted` permette accesso read/write ed è pensata principalmente per ambienti di sviluppo.

- `restricted` limita le operazioni a read-only e introduce limiti sull'esecuzione delle query.

### Sicurezza

Il progetto combina diversi meccanismi:

```text
SQL parsing
+
read-only transactions
+
resource limits
+
PostgreSQL permissions
```

La protezione read-only è quindi costruita su più livelli.

### Interesse per la tesi

È particolarmente interessante perché permette di studiare non solo l'accesso ai dati, ma anche l'esposizione di informazioni sul database tramite strumenti di performance analysis.

Può quindi essere analizzato sia dal punto di vista:

- `integrity`;
- `confidentiality / information disclosure`.

## 6. Google MCP Toolbox for Databases

### Approccio

MCP Toolbox è più ampio di un semplice MCP Server PostgreSQL.

È un framework che permette di:

- utilizzare database prebuilt tools;
- creare custom tools;
- raggruppare tool in toolsets;
- configurare autenticazione e autorizzazione;
- validare parametri.

Supporta PostgreSQL e numerosi altri database.

### Prebuilt tools

Tra gli strumenti disponibili per PostgreSQL troviamo:

- `execute_sql`;
- `list_tables`;
- `list_schemas`;
- `list_roles`;
- strumenti diagnostici;
- statistiche;
- informazioni su indici, lock e query.

Questo rende il server molto più ricco rispetto alla configurazione minimale di DBHub.

### Custom tools

Una caratteristica particolarmente interessante è la possibilità di definire query preimpostate con parametri.

Esempio:

```text
LLM
 ↓
search_customer
 ↓
parameter: name
 ↓
query SQL predefinita
 ↓
PostgreSQL
```

Il modello non deve quindi necessariamente generare SQL arbitrario.

Questo permette di confrontare:

```text
SQL arbitrario
```

con:

```text
custom tool + query parametrizzata
```

### Sicurezza

Toolbox dispone di funzionalità relative a:

- autenticazione OAuth/OIDC;
- authorization;
- tool scopes;
- toolsets;
- parameter validation;
- secure parameters;
- meccanismi read-only;
- controlli a livello database.

### Interesse per la tesi

MCP Toolbox è particolarmente interessante per studiare il principio secondo cui la sicurezza può essere migliorata limitando ciò che l'LLM può chiedere al database.

La domanda diventa:

È più sicuro fornire all'agente un accesso SQL generale oppure una serie di tool specifici e parametrizzati?

## 7. Differenze principali tra i quattro progetti

I quattro progetti rappresentano approcci differenti.

### DBHub

```text
LLM
 ↓
DBHub
 ↓
PostgreSQL
```

Focus:

- semplicità;
- token efficiency;
- guardrail;
- accesso SQL controllato.

### HenkDz

```text
LLM
 ↓
Security Policy
 ↓
PostgreSQL
```

Focus:

- policy MCP;
- risk classification;
- security modes;
- least privilege.

### CrystalDB

```text
LLM
 ↓
Postgres MCP Pro
 ↓
SQL + Performance Analysis
 ↓
PostgreSQL
```

Focus:

- SQL;
- read-only security;
- performance;
- database analysis.

### Google Toolbox

```text
LLM
 ↓
Toolbox
 ↓
Custom / Prebuilt Tools
 ↓
PostgreSQL
```

Focus:

- tool design;
- parameter validation;
- toolsets;
- authentication/authorization.

## 8. Principali superfici di attacco individuate

Dal confronto emergono le seguenti aree di interesse:

- SQL injection;
- prompt injection;
- tool misuse;
- SQL arbitrario;
- privilege escalation;
- excessive database privileges;
- data leakage;
- metadata leakage;
- credential exposure;
- accesso non autorizzato;
- abuso dei tool diagnostici;
- problemi di autenticazione e autorizzazione;
- sicurezza del trasporto MCP;
- accesso a filesystem o altre risorse locali.

## 9. Possibili direttrici sperimentali

I quattro progetti permettono di impostare confronti come:

```text
MCP read-only
        vs
MCP write
```

```text
MCP policy
        vs
PostgreSQL permissions
```

```text
SQL arbitrario
        vs
custom parameterized tools
```

```text
tool limitati
        vs
toolset completo
```

```text
sola esposizione dei dati
        vs
esposizione dei metadata e delle diagnostiche
```

## 10. Possibili domande di ricerca

### Domanda 1

È sufficiente affidarsi ai privilegi PostgreSQL oppure è necessario applicare ulteriori policy a livello MCP?

### Domanda 2

Quanto riduce la superficie di attacco la limitazione dei tool disponibili all'agente?

### Domanda 3

È più sicuro utilizzare custom tools parametrizzati rispetto a consentire SQL arbitrario?

### Domanda 4

Quali informazioni sul database vengono rese disponibili all'agente oltre ai dati contenuti nelle tabelle?

### Domanda 5

Qual è il compromesso tra sicurezza, flessibilità e funzionalità dei diversi MCP Server?

## 11. Conclusione preliminare

L'analisi dei quattro progetti mostra che la sicurezza dell'interazione:

```text
LLM → MCP → Database
```

può essere realizzata a più livelli:

```text
LLM
 ↓
MCP Client
 ↓
MCP Server
 ↓
Security Policy
 ↓
PostgreSQL
 ↓
Database privileges
```

Non esiste quindi un singolo meccanismo sufficiente in ogni scenario.

I quattro progetti forniscono casi di studio complementari:

- DBHub → baseline minimale con guardrail;
- HenkDz → policy di sicurezza esplicita;
- CrystalDB → sicurezza dell'SQL e performance analysis;
- Google MCP Toolbox → progettazione e controllo dei tool.
