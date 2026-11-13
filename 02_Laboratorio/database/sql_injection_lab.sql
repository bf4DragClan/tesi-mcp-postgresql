
-- ============================================================
-- SQL INJECTION LAB
-- Database: pagila
-- Schema: security_lab
--
-- ATTENZIONE:
-- La funzione search_customer_unsafe contiene volutamente
-- una vulnerabilita' SQL Injection.
--
-- Utilizzare esclusivamente nell'ambiente sperimentale locale.
-- ============================================================

BEGIN;


-- ------------------------------------------------------------
-- 1. FUNZIONE VULNERABILE
-- ------------------------------------------------------------
--
-- L'input p_last_name viene concatenato direttamente
-- alla stringa SQL eseguita dinamicamente.
--
-- Un input appositamente costruito puo' alterare
-- la condizione WHERE.
--
-- SECURITY INVOKER:
-- la funzione opera con i privilegi del chiamante.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION security_lab.search_customer_unsafe(
    p_last_name TEXT
)
RETURNS TABLE (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(150)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN

    RETURN QUERY EXECUTE
        'SELECT c.customer_id, c.first_name, c.last_name, c.email ' ||
        'FROM security_lab.test_customers AS c ' ||
        'WHERE c.last_name = ''' || p_last_name || '''';

END;
$function$;


-- ------------------------------------------------------------
-- 2. FUNZIONE SICURA
-- ------------------------------------------------------------
--
-- La query mantiene una struttura SQL fissa.
-- Il valore p_last_name viene trattato come dato.
--
-- Non viene utilizzata concatenazione di input
-- nella stringa SQL.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION security_lab.search_customer_safe(
    p_last_name TEXT
)
RETURNS TABLE (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(150)
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN

    RETURN QUERY
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email
    FROM security_lab.test_customers AS c
    WHERE c.last_name = p_last_name;

END;
$function$;


-- ------------------------------------------------------------
-- 3. REVOCA DEI PRIVILEGI PREDEFINITI
-- ------------------------------------------------------------
--
-- Le funzioni non devono essere eseguibili da PUBLIC.
-- Vengono autorizzati esclusivamente i test con il ruolo
-- read-only dedicato.
-- ------------------------------------------------------------

REVOKE ALL ON FUNCTION
    security_lab.search_customer_unsafe(TEXT)
FROM PUBLIC, mcp_readonly_pagila,
     mcp_writer_pagila, mcp_crud_pagila;

REVOKE ALL ON FUNCTION
    security_lab.search_customer_safe(TEXT)
FROM PUBLIC, mcp_readonly_pagila,
     mcp_writer_pagila, mcp_crud_pagila;


-- ------------------------------------------------------------
-- 4. AUTORIZZAZIONE DEL RUOLO SPERIMENTALE
-- ------------------------------------------------------------

GRANT EXECUTE ON FUNCTION
    security_lab.search_customer_unsafe(TEXT)
TO mcp_readonly_pagila;

GRANT EXECUTE ON FUNCTION
    security_lab.search_customer_safe(TEXT)
TO mcp_readonly_pagila;


-- ------------------------------------------------------------
-- 5. DOCUMENTAZIONE DELLE FUNZIONI
-- ------------------------------------------------------------

COMMENT ON FUNCTION
    security_lab.search_customer_unsafe(TEXT)
IS 'INTENTIONALLY VULNERABLE SQL injection demonstration. Local security lab only.';

COMMENT ON FUNCTION
    security_lab.search_customer_safe(TEXT)
IS 'Safe SQL injection countermeasure demonstration using static SQL.';


COMMIT;

-- ============================================================
-- FINE SCRIPT
-- ============================================================
