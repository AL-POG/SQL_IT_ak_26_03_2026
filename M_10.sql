-- Модуль 10: Использование подзапросов


--------------------------------------------------------------------------------
-- Задание 1. Скалярный подзапрос — фильтрация (Операторы-передовики)
--------------------------------------------------------------------------------
SELECT 
    last_name || ' ' || LEFT(first_name, 1) || '.' AS operator_fio,
    SUM(tons_mined) AS total_production,
    (SELECT ROUND(AVG(op_sum), 2) 
     FROM (SELECT SUM(tons_mined) as op_sum 
           FROM fact_production 
           WHERE date_id BETWEEN 20240301 AND 20240331 
           GROUP BY operator_id) AS avg_query) AS enterprise_avg
FROM fact_production fp
JOIN dim_operator o ON fp.operator_id = o.operator_id
WHERE fp.date_id BETWEEN 20240301 AND 20240331
GROUP BY o.last_name, o.first_name, o.operator_id
HAVING SUM(tons_mined) > (
    SELECT AVG(op_sum) 
    FROM (SELECT SUM(tons_mined) as op_sum 
          FROM fact_production 
          WHERE date_id BETWEEN 20240301 AND 20240331 
          GROUP BY operator_id) AS sub
)
ORDER BY total_production DESC;

--------------------------------------------------------------------------------
-- Задание 2. Подзапрос с IN — Оборудование без простоев
--------------------------------------------------------------------------------
SELECT 
    equipment_name, 
    inventory_number,
    manufacturer
FROM dim_equipment
WHERE equipment_id NOT IN (
    SELECT DISTINCT equipment_id 
    FROM fact_equipment_downtime 
    WHERE date_id BETWEEN 20240301 AND 20240331
)
ORDER BY equipment_name;

--------------------------------------------------------------------------------
-- Задание 3. Коррелированный подзапрос — Последний простой
--------------------------------------------------------------------------------
SELECT 
    e.equipment_name,
    fd.start_time AS last_downtime_start,
    fd.duration_min,
    dr.reason_name
FROM fact_equipment_downtime fd
JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
JOIN dim_downtime_reason dr ON fd.reason_id = dr.reason_id
WHERE fd.start_time = (
    SELECT MAX(start_time)
    FROM fact_equipment_downtime sub
    WHERE sub.equipment_id = fd.equipment_id
      AND sub.start_time < '2024-03-15'
)
ORDER BY e.equipment_name;

--------------------------------------------------------------------------------
-- Задание 4. Подзапрос в SELECT — Доля типа оборудования в добыче
--------------------------------------------------------------------------------
SELECT 
    et.type_name,
    SUM(fp.tons_mined) AS type_total_tons,
    ROUND(100.0 * SUM(fp.tons_mined) / (
        SELECT SUM(tons_mined) 
        FROM fact_production 
        WHERE date_id BETWEEN 20240301 AND 20240331
    ), 2) AS production_share_pct
FROM fact_production fp
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
JOIN dim_equipment_type et ON e.type_id = et.type_id
WHERE fp.date_id BETWEEN 20240301 AND 20240331
GROUP BY et.type_name
ORDER BY production_share_pct DESC;

--------------------------------------------------------------------------------
-- Задание 5. Подзапрос с EXISTS — Шахты с экспортной рудой
--------------------------------------------------------------------------------
SELECT 
    m.mine_name,
    m.location
FROM dim_mine m
WHERE EXISTS (
    SELECT 1 
    FROM fact_production fp
    JOIN dim_ore_grade dog ON fp.ore_grade_id = dog.ore_grade_id
    WHERE fp.mine_id = m.mine_id
      AND dog.grade_code = 'EXPORT'
)
ORDER BY m.mine_name;

--------------------------------------------------------------------------------
-- Задание 6. Многостолбцовый подзапрос — Лучшая смена за день
--------------------------------------------------------------------------------
SELECT 
    date_id,
    shift_id,
    tons_mined AS max_shift_tons
FROM fact_production
WHERE (date_id, tons_mined) IN (
    SELECT date_id, MAX(tons_mined)
    FROM fact_production
    WHERE date_id BETWEEN 20240301 AND 20240307
    GROUP BY date_id
)
ORDER BY date_id;

--------------------------------------------------------------------------------
-- Задание 7. Подзапрос в FROM (Derived Table) — Месячный рост
--------------------------------------------------------------------------------
SELECT 
    month_id,
    monthly_tons,
    prev_month_tons,
    ROUND(((monthly_tons - prev_month_tons) / NULLIF(prev_month_tons, 0) * 100), 2) AS growth_pct
FROM (
    SELECT 
        LEFT(date_id::text, 6) AS month_id,
        SUM(tons_mined) AS monthly_tons,
        LAG(SUM(tons_mined)) OVER (ORDER BY LEFT(date_id::text, 6)) AS prev_month_tons
    FROM fact_production
    GROUP BY LEFT(date_id::text, 6)
) AS monthly_stats
WHERE (monthly_tons - prev_month_tons) / NULLIF(prev_month_tons, 0) > 0.10;

--------------------------------------------------------------------------------
-- Задание 8. Подзапрос в CASE — Оценка технического состояния
--------------------------------------------------------------------------------
SELECT 
    equipment_name,
    CASE 
        WHEN (SELECT MAX(date_id) FROM fact_equipment_downtime fd WHERE fd.equipment_id = e.equipment_id) > 20240325 
             THEN 'Критическое (недавний простой)'
        WHEN (SELECT COUNT(*) FROM fact_equipment_downtime fd WHERE fd.equipment_id = e.equipment_id AND date_id >= 20240301) > 5
             THEN 'Требует ТО'
        ELSE 'Стабильное'
    END AS technical_condition
FROM dim_equipment e;

--------------------------------------------------------------------------------
-- Задание 9. CTE — Топ-3 оператора по каждой шахте
--------------------------------------------------------------------------------
WITH OperatorRating AS (
    SELECT 
        m.mine_name,
        o.last_name || ' ' || o.first_name AS operator_name,
        SUM(fp.tons_mined) AS total_tons,
        DENSE_RANK() OVER (PARTITION BY m.mine_id ORDER BY SUM(fp.tons_mined) DESC) AS rank_in_mine
    FROM fact_production fp
    JOIN dim_mine m ON fp.mine_id = m.mine_id
    JOIN dim_operator o ON fp.operator_id = o.operator_id
    WHERE fp.date_id BETWEEN 20240101 AND 20240331
    GROUP BY m.mine_id, m.mine_name, o.operator_id, o.last_name, o.first_name
)
SELECT * FROM OperatorRating 
WHERE rank_in_mine <= 3
ORDER BY mine_name, rank_in_mine;

--------------------------------------------------------------------------------
-- Задание 10. Комплексный OEE
--------------------------------------------------------------------------------
WITH OEE_Components AS (
    SELECT 
        e.equipment_id,
        e.equipment_name,
        -- Availability
        (SELECT COALESCE(SUM(fp.operating_hours), 0)
         FROM fact_production fp
         WHERE fp.equipment_id = e.equipment_id
           AND fp.date_id BETWEEN 20240101 AND 20240331) AS run_hours,
        (SELECT COALESCE(SUM(fd.duration_min) / 60.0, 0)
         FROM fact_equipment_downtime fd
         WHERE fd.equipment_id = e.equipment_id
           AND fd.date_id BETWEEN 20240101 AND 20240331) AS down_hours,
        -- Performance
        (SELECT SUM(fp.tons_mined) 
         FROM fact_production fp 
         WHERE fp.equipment_id = e.equipment_id) AS actual_tons,
        (SELECT SUM(fp.operating_hours * 50) -- Допустим, 50 т/час - норма
         FROM fact_production fp 
         WHERE fp.equipment_id = e.equipment_id) AS ideal_tons
    FROM dim_equipment e
)
SELECT 
    equipment_name,
    ROUND(run_hours / NULLIF(run_hours + down_hours, 0), 3) AS Availability,
    ROUND(actual_tons / NULLIF(ideal_tons, 0), 3) AS Performance,
    ROUND(
        (run_hours / NULLIF(run_hours + down_hours, 0)) * (actual_tons / NULLIF(ideal_tons, 0)), 3
    ) AS OEE_Score
FROM OEE_Components
WHERE run_hours > 0;
