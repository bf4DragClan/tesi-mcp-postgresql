# Claude Desktop — Configurazione del laboratorio

## Obiettivo

Claude Desktop viene utilizzato come client MCP per verificare l'interazione tra un agente LLM, DBHub e PostgreSQL.

## Architettura

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

## Componenti

### Claude Desktop

Utilizzato come agente LLM e client MCP.

### DBHub

MCP Server utilizzato come intermediario tra il client MCP e PostgreSQL.

### PostgreSQL

Database PostgreSQL 17.11 eseguito all'interno del container Docker tesi-postgres.

Database utilizzato:

`tesi_mcp`

Porta pubblicata sul sistema host:

`5433`

### PostgreSQL role

DBHub utilizza il ruolo:

`mcp_readonly`

Il ruolo dispone di privilegi di sola lettura.

## Operazioni verificate

Sono state verificate tramite Claude Desktop le seguenti operazioni:

- identificazione del database;
- identificazione dell'utente PostgreSQL;
- ricerca delle tabelle;
- conteggio dei clienti;
- lettura di record dalla tabella `app.customers`;
- tentativo di inserimento di un nuovo cliente.

## Risultati

Le operazioni di lettura sono state completate correttamente.

Il tentativo di inserimento è stato rifiutato a causa della configurazione read-only.

Nessuna modifica permanente è stata effettuata sul database.

## Osservazione

Il test dimostra che l'agente LLM può utilizzare i tool MCP per interagire con PostgreSQL, mentre i vincoli di sicurezza della configurazione impediscono le operazioni di scrittura.

Questa configurazione verrà utilizzata come baseline per i successivi test di sicurezza.