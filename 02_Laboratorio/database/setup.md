# Setup del database di laboratorio

## PostgreSQL

Il laboratorio utilizza PostgreSQL 17.11 eseguito all'interno di un container Docker.

Database:

- Nome: `tesi_mcp`
- Container: `tesi-postgres`

## Schema

È stato creato lo schema `app`, contenente le seguenti tabelle:

- `customers`
- `employees`
- `orders`
- `payments`

## Dati iniziali

Il database contiene dati sintetici:

- 20 customers
- 8 employees
- 40 orders
- 30 payments

I dati sono artificiali e vengono utilizzati esclusivamente per gli esperimenti della tesi.

## Ruoli PostgreSQL

### `tesi_user`

Utente amministrativo utilizzato per la configurazione del database e la gestione del laboratorio.

Questo account non deve essere utilizzato dall'MCP Server.

### `mcp_readonly`

Utente PostgreSQL dedicato all'accesso in sola lettura.

Privilegi principali:

- `SELECT`

Non deve poter effettuare operazioni di modifica o cancellazione dei dati.

### `mcp_writer`

Utente PostgreSQL con privilegi limitati di scrittura.

Privilegi principali:

- `SELECT`
- `INSERT`
- `UPDATE`

Non dispone del privilegio:

- `DELETE`

## Obiettivo della configurazione

La presenza di ruoli con privilegi differenti permette di studiare sperimentalmente il principio di least privilege e il ruolo dei privilegi PostgreSQL nella sicurezza di un MCP Server.

L'MCP Server non dovrà utilizzare l'utente amministrativo tesi_user.

## Verifica dei privilegi

Sono stati eseguiti test sui due ruoli PostgreSQL utilizzando `SET LOCAL ROLE` all'interno di una transazione.

### Risultati `mcp_readonly`

- `SELECT`: consentito
- `INSERT`: negato
- modifiche annullate tramite `ROLLBACK`

### Risultati `mcp_writer`

- `SELECT`: consentito
- `INSERT`: consentito
- `UPDATE`: consentito
- `DELETE`: negato
- modifiche annullate tramite `ROLLBACK`

I risultati confermano che i privilegi configurati per i due ruoli funzionano come previsto.

Questa configurazione costituisce la baseline di sicurezza PostgreSQL che verrà utilizzata nella successiva integrazione con gli MCP Server. 

## Integrazione DBHub

DBHub è stato eseguito localmente tramite Node.js utilizzando:

```text
@bytebase/dbhub@1.3.1
```

Configurazione utilizzata:

- transport: HTTP
- host: `127.0.0.1`
- porta HTTP: `8080`
- MCP endpoint: `http://127.0.0.1:8080/mcp`
- Workbench: `http://127.0.0.1:8080`
- database PostgreSQL: `tesi_mcp`
- porta PostgreSQL host: `5433`
- ruolo PostgreSQL utilizzato da DBHub: `mcp_readonly`
- `execute_sql`: configurato con `readonly = true`
- `max_rows`: `1000`

La connessione DBHub → PostgreSQL è stata verificata con successo.

Sono state eseguite le seguenti operazioni tramite il Workbench:

- verifica dell'utente PostgreSQL;
- verifica del database utilizzato;
- lettura dei dati dalla tabella `app.customers`;
- tentativo di `INSERT`.

Le operazioni di lettura sono state eseguite correttamente, mentre l'operazione di inserimento è stata rifiutata come previsto.

La configurazione dimostra quindi il funzionamento combinato di:

- DBHub read-only
- PostgreSQL `mcp_readonly` role

## Test MCP Inspector

Dopo la configurazione di DBHub è stato utilizzato MCP Inspector per verificare la comunicazione tramite protocollo MCP.

Architettura testata:

```text
MCP Inspector
      |
      v
    DBHub
      |
      v
mcp_readonly
      |
      v
 PostgreSQL
```

Sono stati verificati i seguenti casi:

### Identificazione della connessione

La chiamata:

```sql
SELECT current_user;
```

ha restituito:

```text
mcp_readonly
```

La chiamata:

```sql
SELECT current_database();
```

ha restituito:

```text
tesi_mcp
```

### Lettura dei dati

È stata eseguita con successo una query sulla tabella:

```text
app.customers
```

con restituzione dei dati presenti nel database.

### Tentativo di modifica

È stato eseguito un `INSERT` sulla tabella:

```text
app.customers
```

L'operazione è stata rifiutata per mancanza dei privilegi del ruolo `mcp_readonly`.

### Risultato

Il test conferma la seguente catena:

```text
MCP Inspector
      ↓
DBHub
      ↓
PostgreSQL
```

con DBHub configurato in modalità read-only e PostgreSQL configurato con un ruolo che dispone esclusivamente dei privilegi necessari alla lettura.

## Integrazione completa con Claude Desktop

È stata completata una prima integrazione end-to-end tra un agente LLM, un client MCP, DBHub e il database PostgreSQL del laboratorio.

Architettura utilizzata:

```text
Claude Desktop
      |
      v
   MCP Client
      |
      v
     DBHub
      |
      v
mcp_readonly
      |
      v
 PostgreSQL
```

### Configurazione

- LLM/client: Claude Desktop
- MCP Server: DBHub
- Database: PostgreSQL 17.11
- Database name: `tesi_mcp`
- PostgreSQL host port: `5433`
- PostgreSQL role utilizzato da DBHub: `mcp_readonly`
- DBHub: versione verificata durante l'esecuzione del laboratorio
- modalità di accesso: read-only

### Test effettuati

Sono state eseguite richieste in linguaggio naturale tramite Claude Desktop.

#### Identificazione del database

Claude ha utilizzato il tool MCP appropriato per verificare le informazioni sul database.

Risultati:

- database: `tesi_mcp`
- ruolo PostgreSQL: `mcp_readonly`

#### Individuazione delle tabelle

La richiesta relativa alle tabelle presenti nel database ha restituito:

- `app.customers`
- `app.employees`
- `app.orders`
- `app.payments`

per un totale di 4 tabelle.

#### Conteggio dei clienti

La richiesta relativa al numero di clienti presenti in app.customers ha restituito:

`20`

#### Lettura dei dati

È stata eseguita una richiesta per ottenere i primi tre clienti della tabella app.customers.

La richiesta è stata tradotta dall'agente in una tool call MCP che ha provocato l'esecuzione di una query SQL read-only tramite DBHub.

#### Tentativo di modifica

È stata formulata una richiesta in linguaggio naturale per inserire un nuovo cliente.

L'agente non ha potuto completare l'operazione perché la connessione DBHub/PostgreSQL utilizzata nel laboratorio è configurata in modalità read-only.

Il database non ha subito modifiche e il numero di clienti è rimasto pari a 20.

### Risultato della prima integrazione

La configurazione dimostra il funzionamento della catena:

```text
linguaggio naturale
       |
       v
      LLM
       |
       v
   MCP Client
       |
       v
     DBHub
       |
       v
 PostgreSQL
```

e mostra che i controlli implementati a livello MCP e i privilegi del ruolo PostgreSQL possono essere utilizzati congiuntamente per limitare le operazioni dell'agente.

Questa configurazione costituisce la baseline del laboratorio per i successivi esperimenti di sicurezza.


