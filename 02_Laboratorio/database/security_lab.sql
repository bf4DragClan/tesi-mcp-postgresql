
-- ============================================================
-- LABORATORIO MCP SECURITY
-- Database: pagila
-- Schema sperimentale: security_lab
--
-- Eseguire come utente amministrativo postgres.
-- Nessuna password viene memorizzata in questo file.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. CREAZIONE DELLO SCHEMA
-- ------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS security_lab
AUTHORIZATION postgres;

ALTER SCHEMA security_lab OWNER TO postgres;

-- Nessun accesso implicito allo schema per PUBLIC.
REVOKE ALL ON SCHEMA security_lab FROM PUBLIC;


-- ------------------------------------------------------------
-- 2. CREAZIONE DELLE TABELLE
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS security_lab.test_customers (
    customer_id INTEGER PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS security_lab.test_accounts (
    account_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL UNIQUE
        REFERENCES security_lab.test_customers(customer_id),
    balance NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (balance >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'closed'))
);

ALTER TABLE security_lab.test_customers OWNER TO postgres;
ALTER TABLE security_lab.test_accounts OWNER TO postgres;


-- ------------------------------------------------------------
-- 3. INSERIMENTO DEI DATI SINTETICI
-- ------------------------------------------------------------

INSERT INTO security_lab.test_customers
    (customer_id, first_name, last_name, email, notes)
VALUES
    (1, 'Ada', 'Lovelace', 'ada.lovelace@example.test',
     'Synthetic security test record'),
    (2, 'Alan', 'Turing', 'alan.turing@example.test',
     'Synthetic security test record'),
    (3, 'Grace', 'Hopper', 'grace.hopper@example.test',
     'Synthetic security test record'),
    (4, 'Katherine', 'Johnson', 'katherine.johnson@example.test',
     'Synthetic security test record')
ON CONFLICT DO NOTHING;

INSERT INTO security_lab.test_accounts
    (account_id, customer_id, balance, status)
VALUES
    (101, 1, 1250.00, 'active'),
    (102, 2, 800.00, 'active'),
    (103, 3, 2500.00, 'suspended'),
    (104, 4, 600.00, 'active')
ON CONFLICT DO NOTHING;


-- ------------------------------------------------------------
-- 4. CREAZIONE DEI RUOLI DI ACCESSO
-- ------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mcp_writer_pagila'
    ) THEN
        CREATE ROLE mcp_writer_pagila
            LOGIN NOSUPERUSER NOCREATEDB
            NOCREATEROLE NOINHERIT
            NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'mcp_crud_pagila'
    ) THEN
        CREATE ROLE mcp_crud_pagila
            LOGIN NOSUPERUSER NOCREATEDB
            NOCREATEROLE NOINHERIT
            NOREPLICATION NOBYPASSRLS;
    END IF;
END
$$;

-- Impostiamo esplicitamente gli attributi di sicurezza
-- anche sul ruolo read-only già esistente.

ALTER ROLE mcp_readonly_pagila
    LOGIN NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOINHERIT
    NOREPLICATION NOBYPASSRLS;

ALTER ROLE mcp_writer_pagila
    LOGIN NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOINHERIT
    NOREPLICATION NOBYPASSRLS;

ALTER ROLE mcp_crud_pagila
    LOGIN NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOINHERIT
    NOREPLICATION NOBYPASSRLS;


-- ------------------------------------------------------------
-- 5. PRIVILEGI DI CONNESSIONE E ACCESSO ALLO SCHEMA
-- ------------------------------------------------------------

GRANT CONNECT ON DATABASE pagila
TO mcp_readonly_pagila, mcp_writer_pagila, mcp_crud_pagila;

GRANT USAGE ON SCHEMA security_lab
TO mcp_readonly_pagila, mcp_writer_pagila, mcp_crud_pagila;


-- ------------------------------------------------------------
-- 6. RESET DEI PRIVILEGI SULLE TABELLE SPERIMENTALI
-- ------------------------------------------------------------

REVOKE ALL PRIVILEGES
ON ALL TABLES IN SCHEMA security_lab
FROM PUBLIC,
     mcp_readonly_pagila,
     mcp_writer_pagila,
     mcp_crud_pagila;


-- ------------------------------------------------------------
-- 7. PRIVILEGI DEL RUOLO READ-ONLY
-- ------------------------------------------------------------

GRANT SELECT
ON ALL TABLES IN SCHEMA security_lab
TO mcp_readonly_pagila;


-- ------------------------------------------------------------
-- 8. PRIVILEGI DEL RUOLO WRITER
-- ------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON ALL TABLES IN SCHEMA security_lab
TO mcp_writer_pagila;


-- ------------------------------------------------------------
-- 9. PRIVILEGI DEL RUOLO CRUD
-- ------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA security_lab
TO mcp_crud_pagila;


-- ------------------------------------------------------------
-- 10. PRIVILEGI PREDEFINITI PER LE TABELLE FUTURE
-- ------------------------------------------------------------

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA security_lab
GRANT SELECT ON TABLES TO mcp_readonly_pagila;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA security_lab
GRANT SELECT, INSERT, UPDATE
ON TABLES TO mcp_writer_pagila;

ALTER DEFAULT PRIVILEGES
FOR ROLE postgres
IN SCHEMA security_lab
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO mcp_crud_pagila;

COMMIT;

-- ============================================================
-- FINE SCRIPT
-- ============================================================




