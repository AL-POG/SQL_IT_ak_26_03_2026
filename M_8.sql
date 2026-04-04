-- Модуль 8: Проектирование стратегий оптимизированных индексов
--------------------------------------------------------------------------------
-- Задание 1. Анализ селективности
--------------------------------------------------------------------------------
-- Расчет селективности для выбора ведущего столбца в индексе
SELECT 
    'mine_id' AS column_name,
    COUNT(DISTINCT mine_id) AS distinct_values,
    COUNT(*) AS total_rows,
    ROUND(COUNT(DISTINCT mine_id)::numeric / COUNT(*), 6) AS selectivity
FROM fact_production
UNION ALL
SELECT 
    'shaft_id',
    COUNT(DISTINCT shaft_id),
    COUNT(*),
    ROUND(COUNT(DISTINCT shaft_id)::numeric / COUNT(*), 6)
FROM fact_production
UNION ALL
SELECT 
    'date_id',
    COUNT(DISTINCT date_id),
    COUNT(*),
    ROUND(COUNT(DISTINCT date_id)::numeric / COUNT(*), 6)
FROM fact_production;

/* Столбец с самой высокой селективностью (ближе к 1) 
   является лучшим кандидатом на роль первого ключа в композитном индексе.
*/

--------------------------------------------------------------------------------
-- Задание 2. Влияние Fillfactor на хранение
--------------------------------------------------------------------------------
-- Создание индексов с разным коэффициентом заполнения
CREATE INDEX idx_prod_date_ff100 ON fact_production(date_id) WITH (fillfactor = 100);
CREATE INDEX idx_prod_date_ff90 ON fact_production(date_id) WITH (fillfactor = 90);
CREATE INDEX idx_prod_date_ff70 ON fact_production(date_id) WITH (fillfactor = 70);

-- Сравнение размеров и количества страниц
SELECT 
    relname AS index_name,
    pg_size_pretty(pg_relation_size(relid)) AS size,
    relpages AS pages_count
FROM pg_stat_user_indexes i
JOIN pg_class c ON i.indexrelid = c.oid
WHERE relname LIKE 'idx_prod_date_ff%';

--------------------------------------------------------------------------------
-- Задание 3. Порядок столбцов в композитном индексе
--------------------------------------------------------------------------------
-- Сравнение (equipment_id, date_id) vs (date_id, equipment_id)
CREATE INDEX idx_prod_equip_date_v1 ON fact_production(equipment_id, date_id);
CREATE INDEX idx_prod_date_equip_v2 ON fact_production(date_id, equipment_id);

-- Тестовый запрос (диапазон по дате, равенство по оборудованию)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM fact_production 
WHERE equipment_id = 10 AND date_id BETWEEN 20240301 AND 20240310;

--------------------------------------------------------------------------------
-- Задание 4. Оптимизация через Covering Index (INCLUDE)
--------------------------------------------------------------------------------

CREATE INDEX idx_prod_equip_date_covering 
ON fact_production(equipment_id, date_id) 
INCLUDE (tons_mined, fuel_consumed_l);

-- Проверка
EXPLAIN (ANALYZE, BUFFERS)
SELECT equipment_id, date_id, tons_mined, fuel_consumed_l
FROM fact_production
WHERE equipment_id = 5 AND date_id = 20240315;

--------------------------------------------------------------------------------
-- Задание 5. Расширенная статистика (Multivariate Statistics)
--------------------------------------------------------------------------------
-- Для столбцов с функциональной зависимостью
CREATE STATISTICS stat_prod_mine_shaft (dependencies) 
ON mine_id, shaft_id FROM fact_production;

ANALYZE fact_production;

-- Проверка оценки количества строк
EXPLAIN ANALYZE
SELECT * FROM fact_production WHERE mine_id = 1 AND shaft_id = 2;

--------------------------------------------------------------------------------
-- Задание 6. Мониторинг неиспользуемых индексов и Bloat
--------------------------------------------------------------------------------
-- Поиск индексов, которые никогда не использовались
SELECT 
    schemaname, relname AS table_name, indexrelname AS index_name, idx_scan
FROM pg_stat_user_indexes 
WHERE idx_scan = 0 AND indexrelname NOT LIKE 'pg_%' AND indisunique IS FALSE;

--------------------------------------------------------------------------------
-- Задание 7. Оптимизация запросов OEE Dashboard
--------------------------------------------------------------------------------
-- Индексы для ускорения JOIN и агрегации в расчетах OEE
CREATE INDEX idx_oee_prod ON fact_production(equipment_id, date_id, operating_hours, tons_mined);
CREATE INDEX idx_oee_downtime ON fact_equipment_downtime(equipment_id, date_id, duration_min);

--------------------------------------------------------------------------------
-- Задание 8. Управление "раздуванием" (Index Bloat)
--------------------------------------------------------------------------------
-- Имитация обновлений для создания дыр в индексе
UPDATE fact_production SET tons_mined = tons_mined + 0.1 WHERE date_id = 20240301;

-- Пересоздание индекса для устранения фрагментации
REINDEX INDEX idx_prod_date_ff90;

--------------------------------------------------------------------------------
-- Задание 9. Проектирование под типовые сценарии "Руда+"
--------------------------------------------------------------------------------

-- Фильтрация по шахте и дате
CREATE INDEX idx_q1_prod_mine_date ON fact_production(mine_id, date_id);

-- Анализ простоев по оборудованию
CREATE INDEX idx_q2_downtime_equip ON fact_equipment_downtime(equipment_id, start_time);

-- Телеметрия
CREATE INDEX idx_q3_telemetry_alarm ON fact_equipment_telemetry(sensor_id, timestamp) 
WHERE is_alarm = TRUE;

-- Качество руды
CREATE INDEX idx_q4_ore_mine_date ON fact_ore_quality(mine_id, date_id) INCLUDE (fe_content);

-- Неплановые простои
CREATE INDEX idx_q5_downtime_unplanned ON fact_equipment_downtime(date_id) 
WHERE is_planned = FALSE;

--------------------------------------------------------------------------------
-- Задание 10. Финальный аудит
--------------------------------------------------------------------------------
-- Проверка насколько эффективно используется кэш для индексов
SELECT 
    relname AS table_name,
    idx_blks_hit AS cache_hits,
    idx_blks_read AS disk_reads,
    ROUND(idx_blks_hit::numeric / (idx_blks_hit + idx_blks_read + 1) * 100, 2) AS hit_rate_pct
FROM pg_statio_user_indexes
WHERE schemaname = 'public'
ORDER BY hit_rate_pct DESC;

-- Сбор свежей статистики
ANALYZE;




