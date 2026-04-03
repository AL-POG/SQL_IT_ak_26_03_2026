--------------------------------------------------------------------------------
-- Задание 1. Анализ длины строковых полей
--------------------------------------------------------------------------------
SELECT 
    equipment_name,
    LENGTH(equipment_name) AS name_len,
    LENGTH(inventory_number) AS inv_len,
    LENGTH(model) AS model_len,
    LENGTH(manufacturer) AS manuf_len,
    (COALESCE(LENGTH(equipment_name), 0) + 
     COALESCE(LENGTH(inventory_number), 0) + 
     COALESCE(LENGTH(model), 0) + 
     COALESCE(LENGTH(manufacturer), 0)) AS total_text_length
FROM dim_equipment
ORDER BY total_text_length DESC;

--------------------------------------------------------------------------------
-- Задание 2. разбор инвентарного номера
--------------------------------------------------------------------------------
SELECT 
    inventory_number,
    SPLIT_PART(inventory_number, '-', 1) AS prefix,
    SPLIT_PART(inventory_number, '-', 2) AS type_code,
    CAST(SPLIT_PART(inventory_number, '-', 3) AS INTEGER) AS serial_number,
    CASE SPLIT_PART(inventory_number, '-', 2)
        WHEN 'LHD' THEN 'Погрузочно-доставочная машина'
        WHEN 'TRUCK' THEN 'Шахтный самосвал'
        WHEN 'CART' THEN 'Вагонетка'
        WHEN 'SKIP' THEN 'Скиповой подъёмник'
        ELSE 'Неизвестный тип'
    END AS type_description
FROM dim_equipment
ORDER BY type_code, serial_number;

--------------------------------------------------------------------------------
-- Задание 3. Формирование краткого имени оператора
--------------------------------------------------------------------------------
SELECT 
    last_name,
    first_name,
    middle_name,
    -- Формат: Иванов И.П.
    last_name || ' ' || LEFT(first_name, 1) || '.' || 
    COALESCE(LEFT(middle_name, 1) || '.', '') AS short_name_1,
    -- Формат: И.П. Иванов
    LEFT(first_name, 1) || '.' || 
    COALESCE(LEFT(middle_name, 1) || '.', '') || ' ' || last_name AS short_name_2,
    UPPER(last_name) AS upper_last_name,
    LOWER(position) AS lower_position
FROM dim_operator
ORDER BY last_name;

--------------------------------------------------------------------------------
-- Задание 4. Поиск оборудования по шаблону
--------------------------------------------------------------------------------
-- Поиск "ПДМ"
SELECT * FROM dim_equipment WHERE equipment_name LIKE '%ПДМ%';

-- Производители на "S" (регистронезависимо)
SELECT * FROM dim_equipment WHERE manufacturer ILIKE 's%';

-- Шахты с кавычками
SELECT * FROM dim_mine WHERE mine_name LIKE '%"%';

-- Регулярное выражение (серийные номера 001-010 в конце строки)
SELECT * FROM dim_equipment WHERE inventory_number ~ '-0(0[1-9]|10)$';

--------------------------------------------------------------------------------
-- Задание 5. Список оборудования по шахтам (STRING_AGG)
--------------------------------------------------------------------------------
SELECT 
    m.mine_name,
    COUNT(e.equipment_id) AS equipment_count,
    STRING_AGG(e.equipment_name, ', ' ORDER BY e.equipment_name) AS equipment_list,
    STRING_AGG(DISTINCT e.manufacturer, ', ') AS unique_manufacturers
FROM dim_mine m
JOIN dim_equipment e ON m.mine_id = e.mine_id
GROUP BY m.mine_id, m.mine_name;

--------------------------------------------------------------------------------
-- Задание 6. Возраст оборудования
--------------------------------------------------------------------------------
SELECT 
    equipment_name,
    commissioning_date,
    AGE(CURRENT_DATE, commissioning_date) AS full_age,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, commissioning_date)) AS years,
    CURRENT_DATE - commissioning_date AS days,
    CASE 
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, commissioning_date)) < 2 THEN 'Новое'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, commissioning_date)) <= 4 THEN 'Рабочее'
        ELSE 'Требует внимания'
    END AS category
FROM dim_equipment
ORDER BY days DESC;

--------------------------------------------------------------------------------
-- Задание 7. Форматирование дат для отчётов
--------------------------------------------------------------------------------
SELECT 
    commissioning_date,
    TO_CHAR(commissioning_date, 'DD.MM.YYYY') AS format_rus,
    TO_CHAR(commissioning_date, 'DD TMMonth YYYY г.') AS format_full,
    TO_CHAR(commissioning_date, 'YYYY-MM-DD') AS format_iso,
    TO_CHAR(commissioning_date, 'YYYY-"Q"Q') AS format_quarter,
    TO_CHAR(commissioning_date, 'TMDay') AS format_dow,
    TO_CHAR(commissioning_date, 'YYYY-MM') AS year_month
FROM dim_equipment;

--------------------------------------------------------------------------------
-- Задание 8. Анализ простоев по дням недели и часам
--------------------------------------------------------------------------------
-- группировка по дням недели
SELECT 
    EXTRACT(ISODOW FROM start_time) AS dow_number,
    TO_CHAR(start_time, 'TMDay') AS day_of_week,
    COUNT(*) AS downtime_count,
    ROUND(AVG(duration_min), 1) AS avg_duration_min
FROM fact_equipment_downtime
GROUP BY EXTRACT(ISODOW FROM start_time), TO_CHAR(start_time, 'TMDay')
ORDER BY dow_number;

-- Группировка по часам (поиск пикового часа)
SELECT 
    DATE_TRUNC('hour', start_time) AS downtime_hour,
    COUNT(*) AS downtime_count
FROM fact_equipment_downtime
GROUP BY DATE_TRUNC('hour', start_time)
ORDER BY downtime_count DESC;

--------------------------------------------------------------------------------
-- Задание 9. Расчёт графика калибровки датчиков
--------------------------------------------------------------------------------
SELECT 
    e.equipment_name,
    t.sensor_type,
    CURRENT_DATE - s.calibration_date AS days_since_calibration,
    s.calibration_date + INTERVAL '180 days' AS next_calibration_date,
    CASE 
        WHEN CURRENT_DATE - s.calibration_date > 180 THEN 'Просрочена'
        WHEN CURRENT_DATE - s.calibration_date >= 150 THEN 'Скоро'
        ELSE 'В норме'
    END AS status
FROM dim_sensor s
JOIN dim_equipment e ON s.equipment_id = e.equipment_id
JOIN dim_sensor_type t ON s.sensor_type_id = t.sensor_type_id
ORDER BY 
    (CASE WHEN CURRENT_DATE - s.calibration_date > 180 THEN 1 ELSE 2 END),
    next_calibration_date ASC;

--------------------------------------------------------------------------------
-- Задание 10. карточка оборудования
--------------------------------------------------------------------------------
SELECT 
    CONCAT(
        '[', et.type_name, '] ', 
        e.equipment_name, ' (', e.manufacturer, ' ', e.model, ') | ',
        'Шахта: ', m.mine_name, ' | ',
        'Введён: ', TO_CHAR(e.commissioning_date, 'DD.MM.YYYY'), ' | ',
        'Возраст: ', EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.commissioning_date)), ' лет | ',
        'Статус: ', 
        CASE UPPER(e.status)
            WHEN 'ACTIVE' THEN 'АКТИВЕН'
            WHEN 'MAINTENANCE' THEN 'НА ТО'
            WHEN 'DECOMMISSIONED' THEN 'СПИСАН'
            ELSE UPPER(e.status)
        END, ' | ',
        'Видеорег.: ', CASE WHEN e.has_dashcam THEN 'ДА' ELSE 'НЕТ' END, ' | ',
        'Навигация: ', CASE WHEN e.has_navigation THEN 'ДА' ELSE 'НЕТ' END
    ) AS equipment_card
FROM dim_equipment e
JOIN dim_equipment_type et ON e.type_id = et.type_id
JOIN dim_mine m ON e.mine_id = m.mine_id;
