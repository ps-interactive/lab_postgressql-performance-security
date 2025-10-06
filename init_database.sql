-- CarvedRock Database Initialization Script (Minimal Version)
-- Creates tables and minimal data for PostgreSQL performance and security lab

-- Drop existing tables if they exist
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- Create customers table
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    customer_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    zip_code VARCHAR(20),
    country VARCHAR(100) DEFAULT 'USA',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create products table
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    description TEXT,
    sku VARCHAR(50) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table (NO FOREIGN KEY for performance demo)
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending',
    total_amount DECIMAL(10,2),
    shipping_address TEXT,
    billing_address TEXT,
    payment_method VARCHAR(50),
    shipping_method VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table (NO FOREIGN KEYS for performance demo)
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    discount DECIMAL(5,2) DEFAULT 0
);

-- Insert sample customers (5,000 records - enough to show performance issues)
INSERT INTO customers (customer_name, email, phone, address, city, state, zip_code)
SELECT 
    'Customer ' || generate_series,
    'customer' || generate_series || '@carvedrock.com',
    '555-' || LPAD(generate_series::text, 4, '0'),
    generate_series || ' Main Street',
    CASE WHEN random() < 0.3 THEN 'Denver'
         WHEN random() < 0.6 THEN 'Portland'
         WHEN random() < 0.8 THEN 'Seattle'
         ELSE 'Austin'
    END,
    CASE WHEN random() < 0.3 THEN 'CO'
         WHEN random() < 0.6 THEN 'OR'
         WHEN random() < 0.8 THEN 'WA'
         ELSE 'TX'
    END,
    LPAD((random() * 99999)::integer::text, 5, '0')
FROM generate_series(1, 5000);

-- Insert sample products (100 records)
INSERT INTO products (product_name, category, price, stock_quantity, sku)
SELECT 
    'Product ' || generate_series,
    CASE WHEN random() < 0.25 THEN 'Climbing'
         WHEN random() < 0.5 THEN 'Hiking'
         WHEN random() < 0.75 THEN 'Camping'
         ELSE 'Accessories'
    END,
    (random() * 500 + 10)::decimal(10,2),
    (random() * 1000)::integer,
    'SKU-' || LPAD(generate_series::text, 6, '0')
FROM generate_series(1, 100);

-- Insert sample orders (20,000 records - enough to demonstrate slow queries)
INSERT INTO orders (customer_id, order_date, status, total_amount, payment_method, shipping_method, notes)
SELECT 
    (random() * 4999 + 1)::integer,
    CURRENT_DATE - (random() * 365)::integer * INTERVAL '1 day',
    CASE WHEN random() < 0.7 THEN 'completed'
         WHEN random() < 0.9 THEN 'shipped'
         WHEN random() < 0.95 THEN 'pending'
         ELSE 'cancelled'
    END,
    (random() * 1000 + 10)::decimal(10,2),
    CASE WHEN random() < 0.5 THEN 'credit_card'
         WHEN random() < 0.8 THEN 'paypal'
         ELSE 'bank_transfer'
    END,
    CASE WHEN random() < 0.6 THEN 'standard'
         WHEN random() < 0.9 THEN 'express'
         ELSE 'overnight'
    END,
    repeat('Order data padding for bloat. ', 5)
FROM generate_series(1, 20000);

-- Insert sample order items (50,000 records)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT 
    (random() * 19999 + 1)::integer,
    (random() * 99 + 1)::integer,
    (random() * 5 + 1)::integer,
    (random() * 500 + 10)::decimal(10,2)
FROM generate_series(1, 50000);

-- Update order totals based on order items
UPDATE orders o
SET total_amount = (
    SELECT COALESCE(SUM(quantity * unit_price * (1 - discount/100)), 0)
    FROM order_items oi
    WHERE oi.order_id = o.order_id
)
WHERE order_id <= 10000;  -- Only update first half for performance

-- Create bloat by inserting and deleting rows
-- Insert duplicate orders
INSERT INTO orders (customer_id, order_date, status, total_amount, notes)
SELECT customer_id, order_date, 'deleted', total_amount, 'DELETED ROW FOR BLOAT'
FROM orders
WHERE order_id <= 10000;

-- Delete them to create dead tuples
DELETE FROM orders WHERE notes = 'DELETED ROW FOR BLOAT';

-- Insert duplicate customers
INSERT INTO customers (customer_name, email, phone, address, city, state, zip_code)
SELECT 
    customer_name || '_dup',
    'dup_' || email,
    phone,
    address,
    city,
    state,
    zip_code
FROM customers
WHERE customer_id <= 2500;

-- Delete duplicates to create bloat
DELETE FROM customers WHERE customer_name LIKE '%_dup';

-- Add some padding to existing rows to increase table size
UPDATE customers 
SET address = address || ' - ' || repeat('Extra data for size. ', 3)
WHERE customer_id <= 1000;

UPDATE orders 
SET shipping_address = repeat('Shipping address padding. ', 3),
    billing_address = repeat('Billing address padding. ', 3)
WHERE order_id <= 5000;

-- Create a complex query function for performance testing
CREATE OR REPLACE FUNCTION slow_customer_report(days_back INTEGER DEFAULT 90)
RETURNS TABLE(
    customer_name VARCHAR,
    total_orders BIGINT,
    total_spent NUMERIC,
    avg_order NUMERIC,
    last_order TIMESTAMP
) AS $
BEGIN
    RETURN QUERY
    SELECT 
        c.customer_name,
        COUNT(o.order_id),
        SUM(o.total_amount),
        AVG(o.total_amount),
        MAX(o.order_date)
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_date > CURRENT_DATE - (days_back || ' days')::INTERVAL
        AND o.status = 'completed'
    GROUP BY c.customer_name
    HAVING COUNT(o.order_id) > 0
    ORDER BY SUM(o.total_amount) DESC;
END;
$ LANGUAGE plpgsql;

-- Force statistics update
ANALYZE customers;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;
