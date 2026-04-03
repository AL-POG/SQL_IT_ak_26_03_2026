-- Лабораторная работа — Модуль 12: Использование операторов набора


--------------------------------------------------------------------------------
-- Задание 1. UNION ALL — объединённый журнал событий
--------------------------------------------------------------------------------
SELECT 
    'Добыча' AS event_type, 
    e.equipment_name, 
    fp.tons_mined AS value, 
    'тонн' AS unit
FROM fact_production fp
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
WHERE fp.date_id = 20240315

UNION ALL

SELECT 
    'Простой' AS event_type, 
    e.equipment_name, 
    fd.duration_min AS value, 
    'мин.' AS unit
FROM fact_equipment_downtime fd
JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
WHERE fd.date_id = 20240315
ORDER BY equipment_name, event_type;

--------------------------------------------------------------------------------
-- Задание 2. UNION — уникальные шахты с активностью
--------------------------------------------------------------------------------
SELECT m.mine_name
FROM (
    SELECT mine_id FROM fact_production 
    WHERE date_id BETWEEN 20240101 AND 20240331
    UNION -- UNION удаляет дубликаты
    SELECT e.mine_id 
    FROM fact_equipment_downtime fd
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    WHERE fd.date_id BETWEEN 20240101 AND 20240331
) AS active_ids
JOIN dim_mine m ON active_ids.mine_id = m.mine_id;


--------------------------------------------------------------------------------
-- Задание 3. EXCEPT — оборудование без данных о качестве
--------------------------------------------------------------------------------
-- Вариант с EXCEPT
SELECT e.equipment_name, et.type_name
FROM dim_equipment e
JOIN dim_equipment_type et ON e.type_id = et.type_id
WHERE e.equipment_id IN (
    SELECT equipment_id FROM fact_production 
    WHERE date_id BETWEEN 20240101 AND 20240331
    EXCEPT
    SELECT equipment_id FROM fact_ore_quality 
    WHERE date_id BETWEEN 20240101 AND 20240331
);

-- Вариант с NOT EXISTS (альтернатива)
SELECT e.equipment_name, et.type_name
FROM dim_equipment e
JOIN dim_equipment_type et ON e.type_id = et.type_id
WHERE EXISTS (
    SELECT 1 FROM fact_production fp 
    WHERE fp.equipment_id = e.equipment_id AND fp.date_id BETWEEN 20240101 AND 20240331
)
AND NOT EXISTS (
    SELECT 1 FROM fact_ore_quality fq 
    WHERE fq.equipment_id = e.equipment_id AND fq.date_id BETWEEN 20240101 AND 20240331
);

--------------------------------------------------------------------------------
-- Задание 4. INTERSECT — операторы на нескольких типах оборудования
--------------------------------------------------------------------------------
WITH universal_ops AS (
    SELECT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.type_id = et.type_id
    WHERE et.type_code = 'LHD'
    INTERSECT
    SELECT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.type_id = et.type_id
    WHERE et.type_code = 'TRUCK'
)
SELECT 
    o.last_name || ' ' || o.first_name AS fio,
    o.position,
    o.qualification,
    (SELECT ROUND(COUNT(*)*100.0 / (SELECT COUNT(*) FROM dim_operator), 1) FROM universal_ops) AS pct_of_total
FROM dim_operator o
WHERE o.operator_id IN (SELECT operator_id FROM universal_ops);

--------------------------------------------------------------------------------
-- Задание 5. Диаграмма Венна: комплексный анализ
--------------------------------------------------------------------------------
WITH LhdOps AS (
    SELECT DISTINCT operator_id FROM fact_production fp 
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.type_id = et.type_id WHERE et.type_code = 'LHD'
),
TruckOps AS (
    SELECT DISTINCT operator_id FROM fact_production fp 
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.type_id = et.type_id WHERE et.type_code = 'TRUCK'
),
Stats AS (
    SELECT 'Оба типа' AS category, COUNT(*) AS cnt FROM (SELECT * FROM LhdOps INTERSECT SELECT * FROM TruckOps) AS t
    UNION ALL
    SELECT 'Только ПДМ', COUNT(*) AS cnt FROM (SELECT * FROM LhdOps EXCEPT SELECT * FROM TruckOps) AS t
    UNION ALL
    SELECT 'Только самосвал', COUNT(*) AS cnt FROM (SELECT * FROM TruckOps EXCEPT SELECT * FROM LhdOps) AS t
)
SELECT 
    category, 
    cnt, 
    ROUND(cnt * 100.0 / (SELECT SUM(cnt) FROM Stats), 1) AS pct
FROM Stats;

--------------------------------------------------------------------------------
-- Задание 6. LATERAL — топ-5 записей для каждой группы
--------------------------------------------------------------------------------
SELECT m.mine_name, top5.*
FROM dim_mine m
CROSS JOIN LATERAL (
    SELECT 
        d.full_date,
        e.equipment_name,
        dr.reason_name,
        fd.duration_min,
        ROUND(fd.duration_min / 60.0, 1) AS duration_hours
    FROM fact_equipment_downtime fd
    JOIN dim_date d ON fd.date_id = d.date_id
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN dim_downtime_reason dr ON fd.reason_id = dr.reason_id
    WHERE e.mine_id = m.mine_id 
      AND fd.is_planned = FALSE
      AND fd.date_id BETWEEN 20240101 AND 20240331
    ORDER BY fd.duration_min DESC
    LIMIT 5
) top5
WHERE m.status = 'active'
ORDER BY m.mine_name, top5.duration_min DESC;

--------------------------------------------------------------------------------
-- Задание 7. LEFT JOIN LATERAL — последнее показание для каждого датчика
--------------------------------------------------------------------------------
SELECT 
    s.sensor_code,
    st.type_name,
    e.equipment_name,
    last_telemetry.timestamp,
    last_telemetry.sensor_value,
    last_telemetry.is_alarm
FROM dim_sensor s
JOIN dim_sensor_type st ON s.type_id = st.type_id
JOIN dim_equipment e ON s.equipment_id = e.equipment_id
LEFT JOIN LATERAL (
    SELECT timestamp, sensor_value, is_alarm
    FROM fact_equipment_telemetry ft
    WHERE ft.sensor_id = s.sensor_id
    ORDER BY ft.date_id DESC, ft.time_id DESC
    LIMIT 1
) last_telemetry ON TRUE
WHERE s.status = 'active'
ORDER BY last_telemetry.timestamp ASC NULLS FIRST;



--------------------------------------------------------------------------------
-- Задание 8. UNION ALL + агрегация — сводный KPI-отчёт
--------------------------------------------------------------------------------
-- 1. Длинная таблица через UNION ALL
WITH KpiUnion AS (
    SELECT m.mine_name, 'Добыча (тонн)' AS kpi_name, SUM(fp.tons_mined) AS kpi_value
    FROM fact_production fp JOIN dim_mine m ON fp.mine_id = m.mine_id 
    WHERE fp.date_id BETWEEN 20240301 AND 20240331 GROUP BY m.mine_name
    UNION ALL
    SELECT m.mine_name, 'Простои (часы)', ROUND(SUM(fd.duration_min)/60.0, 1)
    FROM fact_equipment_downtime fd 
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN dim_mine m ON e.mine_id = m.mine_id
    WHERE fd.date_id BETWEEN 20240301 AND 20240331 GROUP BY m.mine_name
    UNION ALL
    SELECT m.mine_name, 'Среднее Fe (%)', ROUND(AVG(fq.fe_content), 2)
    FROM fact_ore_quality fq JOIN dim_mine m ON fq.mine_id = m.mine_id
    WHERE fq.date_id BETWEEN 20240301 AND 20240331 GROUP BY m.mine_name
    UNION ALL
    SELECT m.mine_name, 'Тревоги', COUNT(*)::NUMERIC
    FROM fact_equipment_telemetry ft 
    JOIN dim_equipment e ON ft.equipment_id = e.equipment_id
    JOIN dim_mine m ON e.mine_id = m.mine_id
    WHERE ft.date_id BETWEEN 20240301 AND 20240331 AND ft.is_alarm = TRUE GROUP BY m.mine_name
)
-- 2. Разворот в широкую таблицу (Pivot)
SELECT 
    mine_name,
    MAX(CASE WHEN kpi_name = 'Добыча (тонн)' THEN kpi_value END) AS production_tons,
    MAX(CASE WHEN kpi_name = 'Простои (часы)' THEN kpi_value END) AS downtime_hours,
    MAX(CASE WHEN kpi_name = 'Среднее Fe (%)' THEN kpi_value END) AS avg_fe,
    MAX(CASE WHEN kpi_name = 'Тревоги' THEN kpi_value END) AS alarm_count
FROM KpiUnion
GROUP BY mine_name
ORDER BY mine_name;


