CREATE USER powerbi_reader;

CREATE SCHEMA sales;

CREATE TABLE sales.monthly_sales (
    month date NOT NULL,
    region text NOT NULL,
    revenue numeric(12,2) NOT NULL,
    PRIMARY KEY (month, region)
);

INSERT INTO sales.monthly_sales (month, region, revenue) VALUES
    ('2026-01-01', 'East', 125000.00),
    ('2026-01-01', 'West', 142500.00),
    ('2026-02-01', 'East', 131200.00),
    ('2026-02-01', 'West', 151750.00),
    ('2026-03-01', 'East', 138900.00),
    ('2026-03-01', 'West', 158300.00);

GRANT CONNECT ON DATABASE reporting TO powerbi_reader;
GRANT USAGE ON SCHEMA sales TO powerbi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA sales TO powerbi_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA sales GRANT SELECT ON TABLES TO powerbi_reader;
