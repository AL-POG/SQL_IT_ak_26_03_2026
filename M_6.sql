-- Модуль 6: Использование встроенных функций


--------------------------------------------------------------------------------
-- Задание 1. Округление результатов анализов (ROUND, CEIL, FLOOR)
--------------------------------------------------------------------------------
SELECT 
    sample_number, 
    ROUND(fe_content, 1) AS fe_rounded,
    CEIL(sio2_content) AS sio2_ceil, 
    FLOOR(al2o3_content) AS al2o3_floor
FROM fact_ore_quality 
WHERE date_id = 20240315 
ORDER BY fe_rounded DESC;

--------------------------------------------------------------------------------
-- Задание 2. Отклонение от целевого содержания Fe (ABS, SIGN, POWER)
--------------------------------------------------------------------------------
SELECT 
    sample_number, 
    fe_content, 
    (fe_content - 60) AS deviation,
    ABS(fe_content - 60) AS abs_deviation,
    CASE SIGN(fe_content - 60)
        WHEN 1 THEN 'Выше нормы'
        WHEN 0 THEN 'В норме'
        WHEN -1 THEN 'Ниже нормы'
    END AS direction,
    POWER(fe_content - 60, 2) AS squared_dev
FROM fact_ore_quality
WHERE date_id BETWEEN 20240301 AND 20240331
ORDER BY abs_deviation DESC
LIMIT 10;

--------------------------------------------------------------------------------
-- Задание 3. Статистика добычи по сменам (Агрегатные функции)
--------------------------------------------------------------------------------
SELECT
    shift_id,
    CASE shift_id 
        WHEN 1 THEN 'Утренняя' 
        WHEN 2 THEN 'Дневная' 
        WHEN 3 THEN 'Ночная' 
    END AS shift_name,
    COUNT(*) AS record_count,
    SUM(tons_mined) AS total_tons,
    ROUND(AVG(tons_mined), 2) AS avg_tons,
    COUNT(DISTINCT operator_id) AS unique_operators
FROM fact_production
WHERE date_id BETWEEN 20240301 AND 20240331
GROUP BY shift_id
ORDER BY shift_id;

--------------------------------------------------------------------------------
-- Задание 4. Список причин простоев по оборудованию (STRING_AGG)
--------------------------------------------------------------------------------
SELECT
    e.equipment_name,
    STRING_AGG(DISTINCT dr.reason_name, '; ' ORDER BY dr.reason_name) AS reasons,
    SUM(fd.duration_min) AS total_min,
    COUNT(*) AS incidents
FROM fact_equipment_downtime fd
JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
JOIN dim_downtime_reason dr ON fd.reason_id = dr.reason_id
WHERE fd.date_id BETWEEN 20240301 AND 20240331
GROUP BY e.equipment_name
ORDER BY total_min DESC;

--------------------------------------------------------------------------------
-- Задание 5. Преобразование date_id и форматирование (CAST, TO_CHAR)
--------------------------------------------------------------------------------
SELECT
    date_id,
    TO_CHAR(TO_DATE(date_id::VARCHAR, 'YYYYMMDD'), 'DD.MM.YYYY') AS formatted_date,
    SUM(tons_mined) AS total_tons,
    TO_CHAR(SUM(tons_mined), 'FM999G999D00') AS formatted_tons
FROM fact_production
WHERE date_id BETWEEN 20240301 AND 20240307
GROUP BY date_id 
ORDER BY date_id;

--------------------------------------------------------------------------------
-- Задание 6. Классификация проб и процент качества (CASE, NULLIF)
--------------------------------------------------------------------------------
SELECT 
    d.full_date,
    SUM(CASE WHEN q.fe_content >= 65 THEN 1 ELSE 0 END) AS rich_ore,
    SUM(CASE WHEN q.fe_content >= 55 AND q.fe_content < 65 THEN 1 ELSE 0 END) AS medium_ore,
    SUM(CASE WHEN q.fe_content < 55 THEN 1 ELSE 0 END) AS poor_ore,
    COUNT(q.sample_id) AS total_samples,
    ROUND(100.0 * SUM(CASE WHEN q.fe_content >= 60 THEN 1 ELSE 0 END) 
          / NULLIF(COUNT(q.sample_id), 0), 1) AS good_pct
FROM dim_date d
LEFT JOIN fact_ore_quality q ON d.date_id = q.date_id
WHERE d.date_id BETWEEN 20240301 AND 20240331
GROUP BY d.full_date
ORDER BY d.full_date;

--------------------------------------------------------------------------------
-- Задание 7. Безопасные KPI (COALESCE, NULLIF, GREATEST)
--------------------------------------------------------------------------------
SELECT 
    o.last_name, 
    o.first_name,
    SUM(fp.tons_mined) AS total_tons,
    COALESCE(SUM(fp.fuel_consumed_l), 0) AS total_fuel,
    ROUND(SUM(fp.tons_mined) / NULLIF(SUM(fp.trips_count), 0), 2) AS tons_per_trip,
    ROUND(COALESCE(SUM(fp.fuel_consumed_l), 0) / NULLIF(SUM(fp.tons_mined), 0), 3) AS fuel_per_ton,
    -- Пример GREATEST: сравнение суммы добычи в разные периоды или с константой
    GREATEST(
        ROUND(SUM(CASE WHEN shift_id = 1 THEN fp.tons_mined ELSE 0 END) / NULLIF(SUM(CASE WHEN shift_id = 1 THEN fp.trips_count ELSE 0 END), 0), 2),
        ROUND(SUM(CASE WHEN shift_id = 2 THEN fp.tons_mined ELSE 0 END) / NULLIF(SUM(CASE WHEN shift_id = 2 THEN fp.trips_count ELSE 0 END), 0), 2)
    ) AS max_shift_efficiency
FROM fact_production fp
JOIN dim_operator o ON fp.operator_id = o.operator_id
WHERE fp.date_id BETWEEN 20240301 AND 20240331
GROUP BY o.operator_id, o.last_name, o.first_name
ORDER BY tons_per_trip DESC;

--------------------------------------------------------------------------------
-- Задание 8. Анализ пропусков данных (IS NULL, COUNT)
--------------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    -- COUNT(column) не считает NULL
    COUNT(sio2_content) AS sio2_filled,
    COUNT(*) - COUNT(sio2_content) AS sio2_null,
    ROUND(100.0 * COUNT(sio2_content) / COUNT(*), 1) AS sio2_pct,
    
    COUNT(al2o3_content) AS al2o3_filled,
    COUNT(*) - COUNT(al2o3_content) AS al2o3_null,
    ROUND(100.0 * COUNT(al2o3_content) / COUNT(*), 1) AS al2o3_pct,
    
    COUNT(moisture) AS moisture_filled,
    COUNT(density) AS density_filled,
    COUNT(sample_weight_kg) AS weight_filled
FROM fact_ore_quality
WHERE date_id BETWEEN 20240301 AND 20240331;

--------------------------------------------------------------------------------
-- Задание 9. Комплексный отчёт по эффективности оборудования
--------------------------------------------------------------------------------
SELECT
    e.equipment_name,
    et.type_name,
    COUNT(*) AS shift_count,
    ROUND(SUM(fp.tons_mined), 1) AS total_tons,
    ROUND(SUM(fp.operating_hours), 1) AS total_hours,
    ROUND(SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0), 2) AS productivity,
    ROUND(SUM(fp.operating_hours) / NULLIF(COUNT(*) * 8, 0) * 100, 1) AS utilization_pct,
    ROUND(COALESCE(SUM(fp.fuel_consumed_l), 0) / NULLIF(SUM(fp.tons_mined), 0), 3) AS fuel_per_ton,
    CASE 
        WHEN (SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0)) > 20 THEN 'Высокая'
        WHEN (SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0)) > 12 THEN 'Средняя'
        ELSE 'Низкая'
    END AS efficiency_category,
    CASE 
        WHEN COUNT(fp.fuel_consumed_l) = COUNT(*) THEN 'Полные'
        ELSE 'Неполные'
    END AS data_status
FROM fact_production fp
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
JOIN dim_equipment_type et ON e.type_id = et.type_id
WHERE fp.date_id BETWEEN 20240301 AND 20240331
GROUP BY e.equipment_id, e.equipment_name, et.type_name
ORDER BY productivity DESC;

--------------------------------------------------------------------------------
-- Задание 10. Категоризация простоев (Комплексный отчет)
--------------------------------------------------------------------------------
WITH categorized_downtime AS (
    SELECT
        e.equipment_name,
        dr.reason_name,
        COALESCE(fd.duration_min, 0) AS duration_safe,
        CASE
            WHEN COALESCE(fd.duration_min, 0) > 480 THEN 'Критический'
            WHEN COALESCE(fd.duration_min, 0) BETWEEN 120 AND 480 THEN 'Длительный'
            WHEN COALESCE(fd.duration_min, 0) BETWEEN 30 AND 119 THEN 'Средний'
            ELSE 'Короткий'
        END AS category,
        CASE WHEN fd.is_planned THEN 'Плановый' ELSE 'Внеплановый' END AS plan_status,
        CASE WHEN fd.end_time IS NULL THEN 'В процессе' ELSE 'Завершён' END AS completion_status
    FROM fact_equipment_downtime fd
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN dim_downtime_reason dr ON fd.reason_id = dr.reason_id
    WHERE fd.date_id BETWEEN 20240301 AND 20240331
)
SELECT 
    category,
    COUNT(*) AS incidents_count,
    ROUND(SUM(duration_safe) / 60.0, 1) AS total_hours,
    ROUND(100.0 * SUM(duration_safe) / NULLIF((SELECT SUM(duration_safe) FROM categorized_downtime), 0), 1) AS pct_of_total_time
FROM categorized_downtime
GROUP BY category
ORDER BY total_hours DESC;
