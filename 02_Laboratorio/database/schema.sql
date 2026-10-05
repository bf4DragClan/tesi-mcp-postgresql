CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.customers (
    customer_id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(30),
    city VARCHAR(80),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app.employees (
    employee_id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    department VARCHAR(80) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    salary NUMERIC(10,2) NOT NULL CHECK (salary > 0),
    hired_at DATE NOT NULL
);

CREATE TABLE IF NOT EXISTS app.orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES app.customers(customer_id),
    employee_id BIGINT REFERENCES app.employees(employee_id),
    order_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    status VARCHAR(30) NOT NULL
        CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS app.payments (
    payment_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES app.orders(order_id),
    payment_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(30) NOT NULL
        CHECK (payment_method IN ('card', 'paypal', 'bank_transfer')),
    card_last4 CHAR(4)
);

CREATE INDEX IF NOT EXISTS idx_orders_customer
    ON app.orders(customer_id);

CREATE INDEX IF NOT EXISTS idx_orders_employee
    ON app.orders(employee_id);

CREATE INDEX IF NOT EXISTS idx_orders_date
    ON app.orders(order_date);

CREATE INDEX IF NOT EXISTS idx_payments_order
    ON app.payments(order_id);