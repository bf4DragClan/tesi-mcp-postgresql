# Claude Desktop – Configurazione del laboratorio

## 1. Obiettivo

Claude Desktop viene utilizzato come client MCP per verificare l'interazione tra un agente basato su LLM, un MCP Server e un database PostgreSQL.

Nel laboratorio, Claude Desktop comunica con DBHub attraverso il protocollo MCP. DBHub gestisce la connessione a PostgreSQL e mette a disposizione tool per interrogare il database.

L'obiettivo è verificare il funzionamento della comunicazione end-to-end e analizzare i controlli di sicurezza applicati durante l'esecuzione delle query.

## 2. Architettura

L'architettura utilizzata è la seguente:

```text
          Utente
            |
            v
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

Claude Desktop svolge il ruolo di client MCP e agente LLM.

DBHub opera come intermediario tra Claude Desktop e PostgreSQL, esponendo strumenti per l'esecuzione di query e la ricerca degli oggetti del database.

PostgreSQL applica i privilegi associati all'utente utilizzato da DBHub.

## 3. Componenti utilizzati

### 3.1 Claude Desktop

Claude Desktop viene utilizzato come applicazione client MCP.

L'applicazione permette di configurare server MCP locali e di utilizzare i relativi tool durante le conversazioni.

Nel laboratorio viene utilizzata la versione desktop installata su Windows tramite Microsoft Store.

La configurazione del server MCP viene gestita attraverso:

`Settings → Developer → Edit Config`

### 3.2 DBHub

DBHub è il server MCP utilizzato per l'accesso a PostgreSQL.

Repository:

https://github.com/bytebase/dbhub

Il pacchetto viene avviato tramite Node.js e npm:

`@bytebase/dbhub`

La configurazione locale del server è contenuta in:

`02_Laboratorio/dbhub/dbhub-pagila.toml`

La configurazione contiene le credenziali del ruolo PostgreSQL e non deve essere pubblicata nel repository.

### 3.3 PostgreSQL e Pagila

Il database è eseguito in un container Docker.

| Parametro | Valore |
|---|---|
| Container | `tesi-pagila` |
| Database | `pagila` |
| Host | `127.0.0.1` |
| Porta | `5434` |
| Utente MCP | `mcp_readonly_pagila` |

DBHub utilizza un account dedicato con privilegi di sola lettura.

## 4. Configurazione MCP di Claude Desktop

Claude Desktop avvia DBHub localmente utilizzando il transport `stdio`.

La configurazione MCP deve essere inserita nella sezione `mcpServers` del file aperto tramite `Settings → Developer → Edit Config`.

Esempio:

```json
{
  "mcpServers": {
    "dbhub-thesis": {
      "command": "npx",
      "args": [
        "-y",
        "@bytebase/dbhub@latest",
        "--transport",
        "stdio",
        "--config",
        "C:\\PERCORSO\\DEL\\PROGETTO\\02_Laboratorio\\dbhub\\dbhub-pagila.toml"
      ]
    }
  }
}
```

Il percorso della configurazione deve essere sostituito con quello effettivo del progetto sul computer utilizzato.

Se il file JSON contiene già altre impostazioni, queste devono essere mantenute. Il blocco `mcpServers` deve essere inserito nell'oggetto principale del JSON, senza cancellare le preferenze esistenti.

Il nome assegnato al server è:

`dbhub-thesis`

### 4.1 Avvio e verifica

Dopo aver salvato la configurazione:

1. Chiudere completamente Claude Desktop.
2. Riaprire l'applicazione.
3. Aprire una nuova conversazione.
4. Verificare che il server `dbhub-thesis` risulti disponibile.
5. Eseguire una query di prova utilizzando il server MCP.

Il log di avvio di DBHub permette di verificare quale file TOML sia stato caricato.

La configurazione corretta deve riportare:

```text
Configuration source: dbhub-pagila.toml
```

e la sorgente PostgreSQL deve corrispondere al database Pagila sulla porta 5434.

## 5. Tool MCP disponibili

La configurazione DBHub utilizzata nel laboratorio espone due tool principali.

### execute_sql

Permette di eseguire query SQL sul database.

Configurazione:

- sorgente: `pagila`;
- modalità: `readonly = true`;
- limite massimo di righe restituite: `1000`.

La modalità read-only consente soltanto le operazioni SQL ammesse dalla configurazione del server.

### search_objects

Permette di individuare gli oggetti presenti nel database, come tabelle e altri elementi dello schema.

## 6. Test di connessione

Per verificare che Claude Desktop utilizzi il database e il ruolo corretti, è stata eseguita tramite DBHub la seguente query:

```sql
SELECT current_database(), current_user;
```

Risultato ottenuto:

| Campo | Valore |
|---|---|
| `current_database` | `pagila` |
| `current_user` | `mcp_readonly_pagila` |

Il risultato conferma il corretto collegamento tra Claude Desktop, DBHub e PostgreSQL.

## 7. Test delle operazioni SQL

### 7.1 Lettura dei dati

È stata eseguita tramite Claude Desktop la query:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

Il risultato restituito è stato:

`999`

La lettura dei dati è stata completata correttamente.

### 7.2 Tentativo di UPDATE tramite MCP

Per verificare il comportamento del controllo read-only di DBHub è stato eseguito il seguente tentativo:

```sql
UPDATE public.customer
SET first_name = first_name
WHERE false;
```

DBHub ha respinto la query prima dell'invio a PostgreSQL.

Errore restituito:

```text
code: READONLY_VIOLATION

Read-only mode is enabled.
Only the following SQL operations are allowed:
select, with, explain, show
```

È stato quindi eseguito un nuovo conteggio dei clienti:

```sql
SELECT COUNT(*) AS customers
FROM public.customer;
```

Il risultato è rimasto pari a `999`.

Il test dimostra che il controllo read-only di DBHub impedisce l'esecuzione dell'operazione di modifica.

## 8. Verifica indipendente dei privilegi PostgreSQL

Per distinguere il controllo DBHub da quello implementato direttamente nel DBMS, è stato eseguito un test collegandosi a PostgreSQL senza utilizzare l'MCP Server.

Connessione:

```powershell
docker exec -it tesi-pagila psql -h 127.0.0.1 -U mcp_readonly_pagila -d pagila
```

Dopo aver verificato l'identità dell'utente, è stata avviata una transazione ed è stato tentato un UPDATE sulla tabella `public.customer`.

PostgreSQL ha restituito:

```text
ERROR: permission denied for table customer
```

La transazione è stata annullata tramite `ROLLBACK`.

Il numero di clienti è rimasto pari a `999`.

Questo test conferma che PostgreSQL applica autonomamente i privilegi del ruolo, anche quando DBHub non è coinvolto.

## 9. Risultato dell'integrazione

L'integrazione tra Claude Desktop, DBHub e PostgreSQL Pagila è stata verificata con successo.

I test hanno dimostrato che:

- Claude Desktop riesce a utilizzare il server MCP locale;
- DBHub si connette al database `pagila`;
- la connessione utilizza il ruolo `mcp_readonly_pagila`;
- le query di lettura vengono eseguite correttamente;
- DBHub blocca le operazioni non ammesse dalla modalità read-only;
- PostgreSQL impedisce autonomamente l'UPDATE quando viene utilizzato il ruolo privo dei relativi privilegi;
- i dati del database sono rimasti invariati durante i test.

Questa configurazione costituisce la prima integrazione end-to-end del laboratorio e la baseline di riferimento per i successivi esperimenti di sicurezza e confronto tra MCP Server.