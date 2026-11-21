# Claude Desktop – Configurazione del laboratorio MCP

## 1. Obiettivo

Claude Desktop viene utilizzato come client MCP per verificare l'interazione tra un agente basato su Large Language Model (LLM), server MCP DBHub e un database PostgreSQL.

Il laboratorio confronta configurazioni con privilegi differenti, distinguendo:

- i controlli applicati dal tool MCP (in particolare `execute_sql` in modalità read-only);
- i privilegi assegnati al ruolo PostgreSQL;
- le vulnerabilità introdotte dalle funzioni SQL esposte tramite custom tool;
- la gestione di input non affidabili nei tool predefiniti.

Le prove utilizzano esclusivamente tabelle e funzioni sperimentali nello schema `security_lab`, salvo le letture sul dataset originale Pagila.

## 2. Architettura

```text
                      Utente
                        |
                        v
                   Claude Desktop
                     (client MCP)
                        |
       +----------------+----------------+----------------+
       |                |                |                |
       v                v                v                v
  dbhub-thesis     dbhub-writer      dbhub-crud        dbhub-sqli
       |                |                |                |
  mcp_readonly     mcp_writer        mcp_crud        mcp_readonly
       |                |                |                |
       +----------------+----------------+----------------+
                        |
                        v
                   PostgreSQL
                     `pagila`
                   /        \
                public   security_lab
                        ^
                        |
             dbhub-readonly-writer
                (readonly=true)
                        |
                  mcp_writer
```

La quinta connessione, `dbhub-readonly-writer`, riutilizza lo **stesso ruolo PostgreSQL** di `dbhub-writer`, ma imposta `readonly = true` su `execute_sql`. Questo confronto isola il contributo della protezione MCP rispetto ai privilegi del database.

## 3. Componenti utilizzati

### 3.1 Claude Desktop

Claude Desktop avvia i server MCP locali e ne rende disponibili i tool durante le conversazioni. La configurazione si gestisce da **Settings → Developer → Edit Config**, nella sezione `mcpServers`.

### 3.2 DBHub

- Repository: https://github.com/bytebase/dbhub
- Pacchetto npm: `@bytebase/dbhub`
- Trasporto: `stdio`
- Configurazione: un file TOML distinto per ogni connessione.

Durante la preparazione degli esperimenti è stata individuata la versione **1.7.1** nella cache npm. La quinta configurazione è stata impostata con `@bytebase/dbhub@1.7.1`; i profili precedenti erano documentati con `@latest`. La sola presenza della versione in cache **non certifica** quale versione sia stata avviata dalle altre connessioni: per una riproducibilità completa occorre registrarne il comando effettivo o uniformare esplicitamente le versioni.

### 3.3 PostgreSQL e Pagila

| Parametro | Valore |
|---|---|
| Container Docker | `tesi-pagila` |
| Database | `pagila` |
| Host | `127.0.0.1` |
| Porta host | `5434` |
| Versione PostgreSQL verificata | `18.6` |
| Schemi | `public`, `security_lab` |

## 4. Server MCP configurati

Sono state verificate **cinque connessioni MCP**; impiegano **tre ruoli PostgreSQL**.

| Server MCP in Claude | File TOML locale | Ruolo PostgreSQL | `execute_sql` |
|---|---|---|---|
| `dbhub-thesis` | `dbhub-pagila.toml` | `mcp_readonly_pagila` | `readonly = true` |
| `dbhub-writer` | `dbhub-writer.toml` | `mcp_writer_pagila` | `readonly = false` |
| `dbhub-crud` | `dbhub-crud.toml` | `mcp_crud_pagila` | `readonly = false` |
| `dbhub-sqli` | `dbhub-sqli.toml` | `mcp_readonly_pagila` | Non esposto: solo custom tool |
| `dbhub-readonly-writer` | `dbhub-readonly-writer.toml` | `mcp_writer_pagila` | `readonly = true` |

Tutti i file si trovano nella directory `02_Laboratorio/dbhub/`. Le configurazioni reali contengono credenziali e sono escluse da Git; sul repository si pubblicano soltanto i corrispondenti `.toml.example`.

### 4.1 `dbhub-thesis`

Configurazione di riferimento in sola lettura: `mcp_readonly_pagila`, tool `execute_sql` con `readonly = true` e `search_objects`. Permette di leggere Pagila ma non di modificare le tabelle.

### 4.2 `dbhub-writer`

Utilizza `mcp_writer_pagila`, con `SELECT`, `INSERT`, `UPDATE` sulle tabelle sperimentali e senza `DELETE`. Il tool `execute_sql` ha `readonly = false`; è disponibile anche `search_objects`.

### 4.3 `dbhub-crud`

Utilizza `mcp_crud_pagila`, abilitato a `SELECT`, `INSERT`, `UPDATE`, `DELETE` sulle tabelle sperimentali; non ha `TRUNCATE`. `execute_sql` ha `readonly = false`; è disponibile anche `search_objects`.

### 4.4 `dbhub-sqli`

Utilizza `mcp_readonly_pagila` ed espone i custom tool `search_customer_unsafe` e `search_customer_safe`. Non espone un tool `execute_sql` generico. I custom tool richiamano due funzioni PostgreSQL che utilizzano, rispettivamente, SQL dinamico vulnerabile e una query statica sicura. La descrizione completa è in [`../database/sql_injection_lab.md`](../database/sql_injection_lab.md).

### 4.5 `dbhub-readonly-writer`

La connessione aggiunta per approfondire i controlli MCP utilizza:

- File reale: `02_Laboratorio/dbhub/dbhub-readonly-writer.toml`;
- Template pubblico: `02_Laboratorio/dbhub/dbhub-readonly-writer.toml.example`;
- Ruolo PostgreSQL: `mcp_writer_pagila`;
- Schema di lavoro: `security_lab`;
- Tool: `execute_sql` con `readonly = true`, `max_rows = 1000`, e `search_objects`.

Non viene creato un quarto utente PostgreSQL: lo stesso account writer è usato da due server MCP configurati in maniera diversa.

## 5. Configurazione di Claude Desktop

Il file JSON di Claude Desktop contiene un oggetto `mcpServers`. Il seguente è un **esempio completo** con percorsi segnaposto: sostituire `C:/PERCORSO/PROGETTO` con il percorso locale reale prima dell'uso. I separatori `/` nei percorsi Windows sono accettati qui e rendono l'esempio JSON più leggibile.

```json
{
  "mcpServers": {
    "dbhub-thesis": {
      "command": "npx",
      "args": [
        "-y", "@bytebase/dbhub@latest", "--transport", "stdio", "--config",
        "C:/PERCORSO/PROGETTO/02_Laboratorio/dbhub/dbhub-pagila.toml"
      ]
    },
    "dbhub-writer": {
      "command": "npx",
      "args": [
        "-y", "@bytebase/dbhub@latest", "--transport", "stdio", "--config",
        "C:/PERCORSO/PROGETTO/02_Laboratorio/dbhub/dbhub-writer.toml"
      ]
    },
    "dbhub-crud": {
      "command": "npx",
      "args": [
        "-y", "@bytebase/dbhub@latest", "--transport", "stdio", "--config",
        "C:/PERCORSO/PROGETTO/02_Laboratorio/dbhub/dbhub-crud.toml"
      ]
    },
    "dbhub-sqli": {
      "command": "npx",
      "args": [
        "-y", "@bytebase/dbhub@latest", "--transport", "stdio", "--config",
        "C:/PERCORSO/PROGETTO/02_Laboratorio/dbhub/dbhub-sqli.toml"
      ]
    },
    "dbhub-readonly-writer": {
      "command": "npx",
      "args": [
        "-y", "@bytebase/dbhub@1.7.1", "--transport", "stdio", "--config",
        "C:/PERCORSO/PROGETTO/02_Laboratorio/dbhub/dbhub-readonly-writer.toml"
      ]
    }
  }
}
```

**Nota di riproducibilità:** l'esempio conserva `@latest` per le quattro configurazioni preesistenti, come nel documento originario, e registra la versione fissata per la quinta. Se si vuole confrontare le stesse implementazioni del software, occorre fissare e verificare la versione effettiva di tutti i server. Non sostituire il JSON reale di Claude Desktop indiscriminatamente: preservare eventuali altre connessioni e preferenze.

Dopo una modifica al JSON o ai TOML, salvare e riavviare completamente Claude Desktop.

## 6. Verifica dell'identità delle connessioni

La query impiegata, dove il tool generico è disponibile, è:

```sql
SELECT current_database(), current_user;
```

| Server MCP | Database | Utente PostgreSQL | Verifica |
|---|---|---|---|
| `dbhub-thesis` | `pagila` | `mcp_readonly_pagila` | Confermata |
| `dbhub-writer` | `pagila` | `mcp_writer_pagila` | Confermata |
| `dbhub-crud` | `pagila` | `mcp_crud_pagila` | Confermata |
| `dbhub-sqli` | `pagila` | `mcp_readonly_pagila` | Confermata mediante custom tool |
| `dbhub-readonly-writer` | `pagila` | `mcp_writer_pagila` | Confermata tramite `execute_sql` |

La condivisione dello stesso ruolo da parte di `dbhub-writer` e `dbhub-readonly-writer` è intenzionale e costituisce la base del confronto sperimentale.

## 7. Test tramite `dbhub-thesis`

È stata verificata la lettura dei dati originali di Pagila:

```sql
SELECT COUNT(*) AS customers FROM public.customer;
```

Risultato: **999** clienti.

Un tentativo di aggiornamento è stato rifiutato da DBHub:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE false;
```

Risposta: `READONLY_VIOLATION`. Il conteggio successivo è rimasto invariato. Un test indipendente direttamente su PostgreSQL, con il ruolo read-only, ha restituito `permission denied for table customer`. Questi due test mostrano l'esistenza di controlli su livelli distinti, ma questa configurazione da sola non consente di isolare il controllo MCP.

## 8. Test tramite `dbhub-writer`

Sulla tabella `security_lab.test_customers` sono state ottenute le seguenti evidenze:

| Operazione | Record | Esito |
|---|---|---|
| `INSERT` | `customer_id = 9010` | Consentita |
| `UPDATE` | `customer_id = 9010` | Consentita |
| `DELETE` | `customer_id = 9010` | Negata da PostgreSQL (`permission denied`) |

La prova conferma che DBHub non concede privilegi superiori a quelli assegnati al ruolo di connessione.

## 9. Test tramite `dbhub-crud`

Il server `dbhub-crud` ha eliminato il record temporaneo `9010`, inserito e aggiornato il record `9020`, quindi eliminato anche `9020`. La verifica finale ha restituito zero righe per l'identificativo `9020`.

## 10. Esperimento SQL injection tramite `dbhub-sqli`

Il tool `search_customer_unsafe` ha restituito un record con la ricerca legittima `Lovelace`, mentre con il payload `x' OR '1'='1` ha restituito **tutti e quattro** i clienti sintetici. Il tool `search_customer_safe`, con lo stesso payload, ha restituito **zero record**.

È stato inoltre effettuato un test UNION che ha restituito informazioni su `pagila`, sull'utente `mcp_readonly_pagila` e sulla versione PostgreSQL `18.6`; il payload esatto non è stato conservato nella documentazione originale.

Il difetto risiede nella costruzione di una query SQL dinamica nella funzione PostgreSQL vulnerabile, non nella parametrizzazione esterna del custom tool DBHub. Non è stata dimostrata alcuna modifica dei dati o escalation di privilegi. Dettagli: [`../database/sql_injection_lab.md`](../database/sql_injection_lab.md).

## 11. Esperimenti sul controllo read-only di DBHub

Per isolare la protezione MCP è stato utilizzato lo stesso ruolo `mcp_writer_pagila` tramite due server:

| Configurazione | `execute_sql.readonly` | `transaction_read_only` osservato |
|---|---|---|
| `dbhub-writer` | `false` | `off` |
| `dbhub-readonly-writer` | `true` | `on` |

### 11.1 UPDATE diretto

Sul server `dbhub-readonly-writer` la query `UPDATE security_lab.test_customers SET notes = notes WHERE customer_id = -1` è stata respinta con `READONLY_VIOLATION`. Un controllo precedente aveva confermato che l'identificativo `-1` non era presente.

### 11.2 UPDATE annidato in una `WITH`

Anche un CTE con un'istruzione `UPDATE` al suo interno è stato rifiutato con `READONLY_VIOLATION`, benché la query iniziasse con `WITH`.

### 11.3 Funzione con effetti collaterali

Nello schema `security_lab` è stata creata la funzione `readonly_write_probe()` (`SECURITY INVOKER`) che incrementa il valore di `security_lab.mcp_readonly_probe.counter` tramite un `UPDATE`.

- Tramite `dbhub-writer`, `SELECT security_lab.readonly_write_probe()` è riuscita e il contatore è passato da **0** a **1**.
- Tramite `dbhub-readonly-writer`, la stessa invocazione ha restituito l'errore `cannot execute UPDATE in a read-only transaction` (`EXECUTION_ERROR`). Il contatore è rimasto a **1**.

Questo test distingue il controllo del testo SQL dal vincolo della transazione read-only applicato durante l'esecuzione. Non dimostra l'assenza di ogni possibile aggiramento.

La preparazione della tabella e della funzione è stata integrata in [`../database/security_lab.sql`](../database/security_lab.sql); il resoconto completo è in [`../database/dbhub_security_tests.md`](../database/dbhub_security_tests.md).

## 12. Test SQL injection sul tool predefinito `search_objects`

Sul server `dbhub-readonly-writer`, usando **esclusivamente** `search_objects`, sono state confrontate ricerche legittime con input contenenti la stringa SQL `' OR '1'='1`.

| Parametro in esame | Ricerca legittima | Input manipolato | Risultato osservato |
|---|---|---|---|
| `pattern` | 1 tabella | `mcp_readonly_probe' OR '1'='1` | 0 risultati |
| `schema` | `security_lab` | `security_lab' OR '1'='1` | `SCHEMA_NOT_FOUND` |
| `table` | 2 colonne (`id`, `counter`) | `mcp_readonly_probe' OR '1'='1` | 0 risultati |

Non è stata osservata alcuna SQL injection nei casi testati. Il risultato non prova l'immunità generale di `search_objects`. La risposta `SCHEMA_NOT_FOUND` espone anche l'elenco degli schemi disponibili (`public`, `security_lab`), un comportamento da valutare separatamente come divulgazione di metadati.

## 13. Considerazioni finali

Il laboratorio dimostra, negli scenari provati, che:

1. PostgreSQL applica i privilegi dei ruoli anche quando le operazioni sono inviate da un MCP Server.
2. DBHub, con `execute_sql.readonly = true`, rifiuta le scritture dirette e quelle annidate nella `WITH`.
3. La transazione read-only impedisce anche l'`UPDATE` interno a una funzione invocata con `SELECT`, nella configurazione verificata.
4. Un custom tool parametrizzato può comunque richiamare una funzione PostgreSQL vulnerabile se questa costruisce SQL dinamico in modo insicuro.
5. I payload impiegati nei test di `search_objects` non hanno modificato la logica delle ricerche.

Il tool `execute_sql` accetta SQL esplicito per progettazione: questa capacità non equivale da sola a una vulnerabilità SQL injection. Le verifiche read-only e l'analisi dei tool devono quindi essere valutate come aspetti distinti.

I risultati dettagliati sono documentati in [`../database/setup.md`](../database/setup.md), [`../database/sql_injection_lab.md`](../database/sql_injection_lab.md) e [`../database/dbhub_security_tests.md`](../database/dbhub_security_tests.md).
