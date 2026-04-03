-- Модуль 11: Использование табличных выражений


--------------------------------------------------------------------------------
-- Задание 1. Представление — сводка по добыче
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_daily_production_summary AS
SELECT 
    d.full_date,
    m.mine_name,
    s.shift_name,
    COUNT(*) AS record_count,
    SUM(fp.tons_mined) AS total_tons,
    SUM(fp.fuel_consumed_l) AS total_fuel,
    ROUND(AVG(fp.trips_count), 2) AS avg_trips
FROM fact_production fp
JOIN dim_date d ON fp.date_id = d.date_id
JOIN dim_mine m ON fp.mine_id = m.mine_id
JOIN dim_shift s ON fp.shift_id = s.shift_id
GROUP BY d.full_date, m.mine_name, s.shift_name
HAVING COUNT(*) > 5;


--------------------------------------------------------------------------------
-- Задание 2. Представление с проверкой (WITH CHECK OPTION)
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_high_quality_ore AS
SELECT *
FROM practice_fact_ore_quality
WHERE fe_content > 62
WITH CHECK OPTION;


--------------------------------------------------------------------------------
-- Задание 3. Материализованное представление — анализ простоев
--------------------------------------------------------------------------------
CREATE MATERIALIZED VIEW mv_equipment_downtime_stats AS
SELECT 
    e.equipment_id,
    e.equipment_name,
    COUNT(fd.downtime_id) AS total_incidents,
    SUM(fd.duration_min) AS total_duration_min,
    ROUND(AVG(fd.duration_min), 2) AS avg_duration_min,
    MAX(fd.start_time) AS last_incident_date
FROM dim_equipment e
LEFT JOIN fact_equipment_downtime fd ON e.equipment_id = fd.equipment_id
GROUP BY e.equipment_id, e.equipment_name
WITH DATA;

CREATE UNIQUE INDEX idx_mv_equipment_id ON mv_equipment_downtime_stats(equipment_id);


--------------------------------------------------------------------------------
-- Задание 4. Производная таблица (Derived Table) — последний статус датчиков
--------------------------------------------------------------------------------
SELECT *
FROM (
    SELECT 
        s.sensor_id,
        s.sensor_name,
        e.equipment_name,
        ft.sensor_value,
        ft.timestamp,
        ROW_NUMBER() OVER (PARTITION BY s.sensor_id ORDER BY ft.timestamp DESC) as rnk
    FROM dim_sensor s
    JOIN dim_equipment e ON s.equipment_id = e.equipment_id
    JOIN fact_telemetry ft ON s.sensor_id = ft.sensor_id
) AS latest_data
WHERE rnk = 1;

--------------------------------------------------------------------------------
-- Задание 5. CTE — Многоуровневая агрегация (Шахты vs Предприятие)
--------------------------------------------------------------------------------
WITH MineProduction AS (
    SELECT 
        mine_id,
        SUM(tons_mined) AS mine_total
    FROM fact_production
    WHERE date_id BETWEEN 20240301 AND 20240331
    GROUP BY mine_id
),
CompanyAverage AS (
    SELECT AVG(mine_total) AS avg_tons FROM MineProduction
)
SELECT 
    m.mine_name,
    mp.mine_total,
    ROUND(ca.avg_tons, 2) AS company_avg,
    ROUND(mp.mine_total - ca.avg_tons, 2) AS deviation
FROM MineProduction mp
JOIN dim_mine m ON mp.mine_id = m.mine_id
CROSS JOIN CompanyAverage ca;

--------------------------------------------------------------------------------
-- Задание 6. Рекурсивное CTE — Организационная структура
--------------------------------------------------------------------------------
WITH RECURSIVE org_structure AS (
    -- Базовая часть: начальники (у кого manager_id IS NULL)
    SELECT operator_id, first_name, last_name, manager_id, 1 AS level,
           last_name::text AS path
    FROM dim_operator
    WHERE manager_id IS NULL
    
    UNION ALL
    

    SELECT o.operator_id, o.first_name, o.last_name, o.manager_id, os.level + 1,
           os.path || ' -> ' || o.last_name
    FROM dim_operator o
    JOIN org_structure os ON o.manager_id = os.operator_id
)
SELECT * FROM org_structure ORDER BY path;

--------------------------------------------------------------------------------
-- Задание 7. Оконные функции в CTE — Скользящее среднее Fe
--------------------------------------------------------------------------------
WITH MonthlyQuality AS (
    SELECT 
        m.mine_name,
        d.year,
        d.month,
        AVG(q.fe_content) AS avg_fe
    FROM fact_ore_quality q
    JOIN dim_date d ON q.date_id = d.date_id
    JOIN dim_mine m ON q.mine_id = m.mine_id
    GROUP BY m.mine_name, d.year, d.month
)
SELECT 
    *,
    ROUND(AVG(avg_fe) OVER (
        PARTITION BY mine_name 
        ORDER BY year, month 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3m
FROM MonthlyQuality;

--------------------------------------------------------------------------------
-- Задание 8. Pivot (CROSSTAB-логика) через CTE
--------------------------------------------------------------------------------
WITH ShiftPivot AS (
    SELECT 
        date_id,
        SUM(CASE WHEN shift_id = 1 THEN tons_mined ELSE 0 END) AS shift_1_tons,
        SUM(CASE WHEN shift_id = 2 THEN tons_mined ELSE 0 END) AS shift_2_tons,
        SUM(CASE WHEN shift_id = 3 THEN tons_mined ELSE 0 END) AS shift_3_tons
    FROM fact_production
    GROUP BY date_id
)
SELECT 
    d.full_date,
    shift_1_tons, shift_2_tons, shift_3_tons,
    (shift_1_tons + shift_2_tons + shift_3_tons) AS day_total
FROM ShiftPivot sp
JOIN dim_date d ON sp.date_id = d.date_id
ORDER BY d.full_date DESC;

--------------------------------------------------------------------------------
-- Задание 9. Табличная функция (SRF)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_mine_production(p_start_date DATE, p_end_date DATE)
RETURNS TABLE (
    mine_name VARCHAR,
    total_tons NUMERIC,
    total_trips BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.mine_name,
        SUM(fp.tons_mined),
        SUM(fp.trips_count)
    FROM fact_production fp
    JOIN dim_mine m ON fp.mine_id = m.mine_id
    JOIN dim_date d ON fp.date_id = d.date_id
    WHERE d.full_date BETWEEN p_start_date AND p_end_date
    GROUP BY m.mine_name;
END;
$$ LANGUAGE plpgsql;



--------------------------------------------------------------------------------
-- Задание 10. Комплексный отчёт — Дашборд оборудования
--------------------------------------------------------------------------------
WITH EquipmentPerformance AS (
    SELECT 
        equipment_id,
        SUM(tons_mined) AS total_tons,
        SUM(operating_hours) AS total_hours
    FROM fact_production
    GROUP BY equipment_id
),
EquipmentDowntime AS (
    SELECT 
        equipment_id,
        SUM(duration_min) AS total_down_min
    FROM fact_equipment_downtime
    GROUP BY equipment_id
)
SELECT 
    e.equipment_name,
    COALESCE(p.total_tons, 0) AS tons,
    COALESCE(p.total_hours, 0) AS hours,
    ROUND(COALESCE(p.total_tons, 0) / NULLIF(p.total_hours, 0), 2) AS productivity,
    ROUND(COALESCE(d.total_down_min, 0) / 60.0, 1) AS downtime_hours
FROM dim_equipment e
LEFT JOIN EquipmentPerformance p ON e.equipment_id = p.equipment_id
LEFT JOIN EquipmentDowntime d ON e.equipment_id = d.equipment_id;

