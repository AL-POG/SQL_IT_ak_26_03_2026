-- Модуль 7: Введение в индексы


--------------------------------------------------------------------------------
-- Задание 1. Анализ существующих индексов
--------------------------------------------------------------------------------

SELECT 
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

--------------------------------------------------------------------------------
-- Задание 2. Анализ плана выполнения (Seq Scan)
--------------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fact_production 
WHERE tons_mined > 500;



--------------------------------------------------------------------------------
-- Задание 3. Оптимизация по расходу топлива (B-tree индекс)
--------------------------------------------------------------------------------
-- 1. Замер до
EXPLAIN ANALYZE 
SELECT equipment_id, SUM(fuel_consumed_l)
FROM fact_production
WHERE fuel_consumed_l > 300
GROUP BY equipment_id;

-- 2. Создание индекса
CREATE INDEX idx_fact_production_fuel ON fact_production(fuel_consumed_l);

-- 3. Замер после
EXPLAIN ANALYZE 
SELECT equipment_id, SUM(fuel_consumed_l)
FROM fact_production
WHERE fuel_consumed_l > 300
GROUP BY equipment_id;

--------------------------------------------------------------------------------
-- Задание 4. Частичный индекс (Partial Index)
--------------------------------------------------------------------------------

CREATE INDEX idx_telemetry_alarm_active 
ON fact_equipment_telemetry(sensor_id) 
WHERE is_alarm = TRUE;


EXPLAIN ANALYZE
SELECT * FROM fact_equipment_telemetry 
WHERE is_alarm = TRUE AND sensor_id = 10;

--------------------------------------------------------------------------------
-- Задание 5. Композитный индекс (Composite Index)
--------------------------------------------------------------------------------
-- Порядок столбцов важен для правила "левого префикса"
CREATE INDEX idx_prod_mine_date ON fact_production(mine_id, date_id);

-- Запрос, использующий оба поля
EXPLAIN ANALYZE
SELECT * FROM fact_production WHERE mine_id = 1 AND date_id = 20240315;

-- Запрос, использующий только левое поле
EXPLAIN ANALYZE
SELECT * FROM fact_production WHERE mine_id = 1;

--------------------------------------------------------------------------------
-- Задание 6. Индекс по выражению (Expression Index)
--------------------------------------------------------------------------------
-- Индекс для регистронезависимого поиска
CREATE INDEX idx_equip_name_lower ON dim_equipment(LOWER(equipment_name));

-- Проверка
EXPLAIN ANALYZE
SELECT * FROM dim_equipment WHERE LOWER(equipment_name) = 'самосвал';

--------------------------------------------------------------------------------
-- Задание 7. Покрывающий индекс (Covering Index / Index Only Scan)
--------------------------------------------------------------------------------

CREATE INDEX idx_prod_equip_tons ON fact_production(equipment_id) INCLUDE (tons_mined);


EXPLAIN ANALYZE
SELECT equipment_id, tons_mined 
FROM fact_production 
WHERE equipment_id = 5;

--------------------------------------------------------------------------------
-- Задание 8. BRIN-индекс для больших таблиц
--------------------------------------------------------------------------------

CREATE INDEX idx_prod_date_brin ON fact_production USING BRIN (date_id);


SELECT 
    pg_size_pretty(pg_relation_size('idx_prod_mine_date'::regclass)) AS btree_size,
    pg_size_pretty(pg_relation_size('idx_prod_date_brin'::regclass)) AS brin_size;

--------------------------------------------------------------------------------
-- Задание 9. Влияние индексов на INSERT
--------------------------------------------------------------------------------
-- 1. Замер времени вставки в таблицу с индексами
\timing on
INSERT INTO fact_production (date_id, shift_id, equipment_id, operator_id, tons_mined)
SELECT 20240401, 1, 1, 1, random()*100 FROM generate_series(1, 10000);
\timing off



--------------------------------------------------------------------------------
-- Задание 10. Комплексная оптимизация (Финал)
--------------------------------------------------------------------------------


-- Итоговый отчет по состоянию кэша и чтений
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit)  as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as hit_ratio
FROM pg_statio_user_tables;

-- Очистка тестовых данных
DELETE FROM fact_production WHERE date_id = 20240401;

