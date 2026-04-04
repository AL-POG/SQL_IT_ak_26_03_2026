-- Модуль 14: Свёртывание и наборы группировки

CREATE EXTENSION IF NOT EXISTS tablefunc;

--------------------------------------------------------------------------------
-- Задание 1. ROLLUP — сменный рапорт с подитогами
--------------------------------------------------------------------------------
SELECT 
    CASE WHEN GROUPING(m.mine_name) = 1 THEN '== ИТОГО ПО КОМПАНИИ ==' 
         ELSE m.mine_name END AS mine,
    CASE WHEN GROUPING(s.shift_name) = 1 AND GROUPING(m.mine_name) = 0 THEN 'Итого по шахте' 
         ELSE s.shift_name END AS shift,
    SUM(fp.tons_mined) AS total_tons,
    COUNT(DISTINCT fp.equipment_id) AS equipment_count
FROM fact_production fp
JOIN dim_mine m ON fp.mine_id = m.mine_id
JOIN dim_shift s ON fp.shift_id = s.shift_id
WHERE fp.date_id = 20240115
GROUP BY ROLLUP(m.mine_name, s.shift_name)
ORDER BY m.mine_name NULLS LAST, s.shift_name NULLS LAST;

--------------------------------------------------------------------------------
-- Задание 2. CUBE — многомерный анализ оборудования
--------------------------------------------------------------------------------
SELECT 
    COALESCE(m.mine_name, 'Все шахты') AS mine,
    COALESCE(et.type_name, 'Все типы') AS equip_type,
    ROUND(AVG(fp.tons_mined), 1) AS avg_tons,
    SUM(fp.tons_mined) AS total_tons
FROM fact_production fp
JOIN dim_mine m ON fp.mine_id = m.mine_id
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
JOIN dim_equipment_type et ON e.type_id = et.type_id
GROUP BY CUBE(m.mine_name, et.type_name)
ORDER BY mine, equip_type;

--------------------------------------------------------------------------------
-- Задание 3. GROUPING SETS — специфические срезы данных
--------------------------------------------------------------------------------
SELECT 
    m.mine_name,
    o.last_name,
    et.type_name,
    SUM(fp.tons_mined) AS tons
FROM fact_production fp
JOIN dim_mine m ON fp.mine_id = m.mine_id
JOIN dim_operator o ON fp.operator_id = o.operator_id
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
JOIN dim_equipment_type et ON e.type_id = et.type_id
GROUP BY GROUPING SETS (
    (m.mine_name, et.type_name), -- Шахта + Тип техники
    (o.last_name), -- Личная выработка оператора
    () -- Общий итог
)
ORDER BY m.mine_name, o.last_name, et.type_name;

--------------------------------------------------------------------------------
-- Задание 4. PIVOT — добыча по месяцам
--------------------------------------------------------------------------------
SELECT * FROM crosstab(
    'SELECT m.mine_name, d.month, SUM(fp.tons_mined)
     FROM fact_production fp
     JOIN dim_mine m ON fp.mine_id = m.mine_id
     JOIN dim_date d ON fp.date_id = d.date_id
     WHERE d.year = 2024 AND d.month <= 3
     GROUP BY 1, 2 ORDER BY 1, 2',
    'SELECT generate_series(1,3)'
) AS ct(mine_name TEXT, jan NUMERIC, feb NUMERIC, mar NUMERIC);

--------------------------------------------------------------------------------
-- Задание 5. Комплексный KPI отчёт
--------------------------------------------------------------------------------
WITH RawData AS (
    -- Добыча
    SELECT 
        COALESCE(m.mine_name, '== ИТОГО ==') AS mine,
        'Добыча (тонн)' AS metric,
        SUM(CASE WHEN d.month = 1 THEN fp.tons_mined END) AS jan,
        SUM(CASE WHEN d.month = 2 THEN fp.tons_mined END) AS feb,
        SUM(CASE WHEN d.month = 3 THEN fp.tons_mined END) AS mar,
        SUM(fp.tons_mined) AS q1_total
    FROM fact_production fp
    JOIN dim_mine m ON fp.mine_id = m.mine_id
    JOIN dim_date d ON fp.date_id = d.date_id
    WHERE d.year = 2024 AND d.month <= 3
    GROUP BY ROLLUP(m.mine_name)
    
    UNION ALL

    -- Простои (перевод в часы)
    SELECT 
        COALESCE(m.mine_name, '== ИТОГО ==') AS mine,
        'Простои (час)' AS metric,
        ROUND(SUM(CASE WHEN d.month = 1 THEN fd.duration_min END)/60.0, 1),
        ROUND(SUM(CASE WHEN d.month = 2 THEN fd.duration_min END)/60.0, 1),
        ROUND(SUM(CASE WHEN d.month = 3 THEN fd.duration_min END)/60.0, 1),
        ROUND(SUM(fd.duration_min)/60.0, 1)
    FROM fact_equipment_downtime fd
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN dim_mine m ON e.mine_id = m.mine_id
    JOIN dim_date d ON fd.date_id = d.date_id
    WHERE d.year = 2024 AND d.month <= 3
    GROUP BY ROLLUP(m.mine_name)
)
SELECT 
    mine, metric, jan, feb, mar, q1_total,
    CASE 
        WHEN jan > 0 THEN ROUND(((feb - jan) / jan) * 100, 1) 
        ELSE NULL 
    END AS feb_vs_jan_pct
FROM RawData
ORDER BY (mine = '== ИТОГО =='), mine, metric DESC;

