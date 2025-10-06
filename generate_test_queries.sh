#!/bin/bash
# Generate test queries to populate pg_stat_statements

echo "Generating test queries to simulate workload..."

# Run various queries to populate statistics
sudo -u postgres psql carvedrock <<EOF
-- Simple queries
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM orders;
SELECT COUNT(*) FROM products;

-- Join queries
SELECT c.customer_name, COUNT(o.order_id)
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_name
LIMIT 100;

-- Aggregation queries
SELECT 
    DATE_TRUNC('month', order_date) as month,
    COUNT(*) as orders,
    SUM(total_amount) as revenue
FROM orders
WHERE order_date > CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE_TRUNC('month', order_date);

-- Subqueries
SELECT customer_name
FROM customers
WHERE customer_id IN (
    SELECT customer_id 
    FROM orders 
    WHERE total_amount > 500
    GROUP BY customer_id
    HAVING COUNT(*) > 5
);

-- Complex joins
SELECT 
    p.product_name,
    p.category,
    COUNT(DISTINCT o.customer_id) as unique_customers,
    SUM(oi.quantity) as total_sold
FROM products p
JOIN order_items oi ON p.product_id = oi.product_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_date > CURRENT_DATE - INTERVAL '30 days'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_sold DESC
LIMIT 20;

-- Slow query without index
SELECT *
FROM orders o1
WHERE total_amount > (
    SELECT AVG(total_amount) 
    FROM orders o2 
    WHERE o2.customer_id = o1.customer_id
);

EOF

echo "Test queries completed."
