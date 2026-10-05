INSERT INTO app.customers (full_name, email, phone, city)
SELECT
    'Customer ' || i,
    'customer' || i || '@example.com',
    '+39 02 5555 ' || LPAD(i::text, 4, '0'),
    CASE (i % 5)
        WHEN 0 THEN 'Milano'
        WHEN 1 THEN 'Bergamo'
        WHEN 2 THEN 'Brescia'
        WHEN 3 THEN 'Verona'
        ELSE 'Torino'
    END
FROM generate_series(1, 20) AS i;


INSERT INTO app.employees (full_name, department, email, salary, hired_at)
VALUES
    ('Luca Bianchi', 'Sales', 'luca.bianchi@example.com', 32000, '2021-03-15'),
    ('Marco Rossi', 'IT', 'marco.rossi@example.com', 42000, '2020-06-10'),
    ('Anna Verdi', 'Finance', 'anna.verdi@example.com', 45000, '2019-11-20'),
    ('Giulia Ferrari', 'HR', 'giulia.ferrari@example.com', 35000, '2022-01-17'),
    ('Matteo Conti', 'IT', 'matteo.conti@example.com', 39000, '2023-04-03'),
    ('Sara Romano', 'Sales', 'sara.romano@example.com', 33000, '2022-09-12'),
    ('Davide Colombo', 'Finance', 'davide.colombo@example.com', 47000, '2018-07-09'),
    ('Elisa Ricci', 'HR', 'elisa.ricci@example.com', 36000, '2021-12-01');


INSERT INTO app.orders (customer_id, employee_id, order_date, amount, status)
SELECT
    ((i - 1) % 20) + 1,
    ((i - 1) % 8) + 1,
    CURRENT_TIMESTAMP - ((i * 3) || ' days')::interval,
    ROUND((50 + (i * 17.35))::numeric, 2),
    CASE (i % 4)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'paid'
        WHEN 2 THEN 'shipped'
        ELSE 'cancelled'
    END
FROM generate_series(1, 40) AS i;


INSERT INTO app.payments (
    order_id,
    payment_date,
    amount,
    payment_method,
    card_last4
)
SELECT
    o.order_id,
    o.order_date + INTERVAL '1 hour',
    o.amount,
    CASE (o.order_id % 3)
        WHEN 0 THEN 'card'
        WHEN 1 THEN 'paypal'
        ELSE 'bank_transfer'
    END,
    CASE
        WHEN o.order_id % 3 = 0
        THEN LPAD((1000 + o.order_id)::text, 4, '0')
        ELSE NULL
    END
FROM app.orders o
WHERE o.status <> 'cancelled';