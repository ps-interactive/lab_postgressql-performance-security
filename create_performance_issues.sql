-- Create Performance Issues for Lab Exercise

-- Drop all existing indexes except primary keys
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT indexname, tablename 
        FROM pg_indexes 
        WHERE schemaname = 'public' 
        AND indexname NOT LIKE '%_pkey'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || r.indexname;
    END LOOP;
END $$;

-- Create a deliberately slow function without indexes
CREATE OR REPLACE FUNCTION find_customers_with_multiple_recent_orders()
RETURNS TABLE(customer_name VARCHAR, order_count BIGINT, total_spent NUMERIC)
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.customer_name,
        COUNT(*) as order_count,
        SUM(o.total_amount) as total_spent
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE EXISTS (
        SELECT 1 FROM orders o2 
        WHERE o2.customer_id = c.customer_id 
        AND o2.order_date > CURRENT_DATE - INTERVAL '30 days'
    )
    AND EXISTS (
        SELECT 1 FROM orders o3 
        WHERE o3.customer_id = c.customer_id 
        GROUP BY o3.customer_id 
        HAVING COUNT(*) > 3
    )
    GROUP BY c.customer_name;
END;
$$ LANGUAGE plpgsql;

-- Create a view with inefficient correlated subqueries
CREATE OR REPLACE VIEW slow_order_analysis AS
SELECT 
    o.order_id,
    o.customer_id,
    o.total_amount,
    (SELECT COUNT(*) FROM order_items WHERE order_id = o.order_id) as item_count,
    (SELECT SUM(quantity) FROM order_items WHERE order_id = o.order_id) as total_items,
    (SELECT customer_name FROM customers WHERE customer_id = o.customer_id) as customer_name,
    (SELECT COUNT(*) FROM orders o2 WHERE o2.customer_id = o.customer_id AND o2.order_date < o.order_date) as previous_orders
FROM orders o
WHERE o.status = 'completed';

-- Create an inefficient customer summary view
CREATE OR REPLACE VIEW slow_customer_summary AS
SELECT 
    c.*,
    (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.customer_id) as order_count,
    (SELECT SUM(total_amount) FROM orders o WHERE o.customer_id = c.customer_id) as total_spent,
    (SELECT MAX(order_date) FROM orders o WHERE o.customer_id = c.customer_id) as last_order,
    (SELECT MIN(order_date) FROM orders o WHERE o.customer_id = c.customer_id) as first_order,
    (SELECT AVG(total_amount) FROM orders o WHERE o.customer_id = c.customer_id) as avg_order_value
FROM customers c;

-- Create a simple audit log table
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    operation VARCHAR(50),
    user_name VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_data JSONB,
    new_data JSONB
);

-- Insert minimal audit log data (1000 records)
INSERT INTO audit_log (table_name, operation, user_name, old_data, new_data)
SELECT 
    CASE WHEN random() < 0.5 THEN 'orders' ELSE 'customers' END,
    CASE WHEN random() < 0.3 THEN 'INSERT'
         WHEN random() < 0.6 THEN 'UPDATE'
         WHEN random() < 0.9 THEN 'SELECT'
         ELSE 'DELETE'
    END,
    'app_user',
    '{"id": ' || generate_series || '}',
    '{"id": ' || generate_series || ', "modified": true}'
FROM generate_series(1, 1000);

-- Disable autovacuum temporarily to allow bloat to accumulate
ALTER TABLE orders SET (autovacuum_enabled = false);
ALTER TABLE customers SET (autovacuum_enabled = false);
ALTER TABLE order_items SET (autovacuum_enabled = false);

-- Create a function that will be deliberately slow
CREATE OR REPLACE FUNCTION calculate_customer_lifetime_value(cust_id INTEGER)
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC;
    avg_order NUMERIC;
    order_frequency NUMERIC;
BEGIN
    -- Inefficient calculation with multiple queries
    SELECT SUM(total_amount) INTO total
    FROM orders WHERE customer_id = cust_id;
    
    SELECT AVG(total_amount) INTO avg_order
    FROM orders WHERE customer_id = cust_id;
    
    SELECT COUNT(*)::NUMERIC / 
           GREATEST(1, EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))))
    INTO order_frequency
    FROM orders WHERE customer_id = cust_id;
    
    RETURN COALESCE(total + (avg_order * order_frequency * 2), 0);
END;
$$ LANGUAGE plpgsql;

-- Reset statistics to hide optimization opportunities
SELECT pg_stat_reset();

-- Set low work_mem to cause disk-based sorting
ALTER SYSTEM SET work_mem = '1MB';

-- Set low shared_buffers to reduce caching
ALTER SYSTEM SET shared_buffers = '32MB';

-- Disable parallel queries to make things slower
ALTER SYSTEM SET max_parallel_workers_per_gather = 0;

-- Set random_page_cost high to discourage index usage
ALTER SYSTEM SET random_page_cost = 100;

-- Apply settings
SELECT pg_reload_conf();

-- Create a materialized view that needs refresh
CREATE MATERIALIZED VIEW IF NOT EXISTS sales_summary AS
SELECT 
    DATE_TRUNC('month', order_date) as month,
    COUNT(*) as order_count,
    SUM(total_amount) as total_sales,
    AVG(total_amount) as avg_order_value,
    MIN(total_amount) as min_order,
    MAX(total_amount) as max_order
FROM orders
WHERE status = 'completed'
GROUP BY DATE_TRUNC('month', order_date);

-- Don't refresh it, leaving it stale
-- REFRESH MATERIALIZED VIEW sales_summary;

-- Create one more complex view for testing
CREATE OR REPLACE VIEW customer_order_patterns AS
SELECT 
    c.customer_id,
    c.customer_name,
    COUNT(DISTINCT DATE_TRUNC('month', o.order_date)) as active_months,
    COUNT(DISTINCT DATE_TRUNC('week', o.order_date)) as active_weeks,
    COUNT(o.order_id) as total_orders,
    AVG(o.total_amount) as avg_order_value,
    STDDEV(o.total_amount) as order_value_stddev,
    MAX(o.order_date) as last_order_date,
    MIN(o.order_date) as first_order_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_name;

-- Add a comment about the performance issues
COMMENT ON SCHEMA public IS 'Database intentionally configured with performance issues for training purposes';
