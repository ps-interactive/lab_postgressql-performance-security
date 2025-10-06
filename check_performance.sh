#!/bin/bash
# Check current database performance metrics

echo "==================================="
echo "PostgreSQL Performance Check"
echo "==================================="
echo ""

# Check database size
echo "Database Size:"
sudo -u postgres psql -d carvedrock -t -c "SELECT pg_size_pretty(pg_database_size('carvedrock'));"
echo ""

# Check table sizes and bloat
echo "Table Sizes and Bloat:"
sudo -u postgres psql -d carvedrock -x -c "
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup > 0 
        THEN round(n_dead_tup * 100.0 / n_live_tup, 2) 
        ELSE 0 
    END AS dead_percentage
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
echo ""

# Check slow queries
echo "Slowest Queries (from pg_stat_statements):"
sudo -u postgres psql -d carvedrock -c "
SELECT 
    substr(query,1,60) as query_preview,
    calls,
    round(mean_exec_time::numeric,2) as avg_ms,
    round(total_exec_time::numeric,2) as total_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 5;"
echo ""

# Check index usage
echo "Index Usage Statistics:"
sudo -u postgres psql -d carvedrock -c "
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan
LIMIT 10;"
echo ""

# Check current configuration
echo "Current Memory Configuration:"
sudo -u postgres psql -c "SHOW shared_buffers;"
sudo -u postgres psql -c "SHOW work_mem;"
sudo -u postgres psql -c "SHOW effective_cache_size;"
echo ""

echo "Performance check complete."
