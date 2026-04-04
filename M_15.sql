

-- Лабораторная работа — Модуль 15: Выполнение хранимых процедур



--------------------------------------------------------------------------------
-- Задание 1. Скалярная функция — расчёт OEE
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calc_oee(
    p_operating_hours NUMERIC, 
    p_planned_hours NUMERIC, 
    p_actual_tons NUMERIC, 
    p_target_tons NUMERIC
)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    -- Проверка на деление на ноль
    IF p_planned_hours = 0 OR p_target_tons = 0 OR p_planned_hours IS NULL OR p_target_tons IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN ROUND(
        (p_operating_hours / p_planned_hours) * (p_actual_tons / p_target_tons) * 100, 
        1
    );
END;
$$;

SELECT calc_oee(10, 12, 80, 100);

--------------------------------------------------------------------------------
-- Задание 2. Условная логика — классификация простоев
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION classify_downtime(p_duration_min INT)
RETURNS TEXT LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN CASE 
        WHEN p_duration_min < 30 THEN 'Кратковременный'
        WHEN p_duration_min BETWEEN 30 AND 120 THEN 'Средний'
        WHEN p_duration_min > 120 THEN 'Длительный'
        ELSE 'Неизвестно'
    END;
END;
$$;


SELECT equipment_id, duration_min, classify_downtime(duration_min) FROM fact_equipment_downtime;

--------------------------------------------------------------------------------
-- Задание 3. Табличная функция — сводка по технике
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_equipment_summary(p_mine_id INT)
RETURNS TABLE(
    equipment_name TEXT,
    total_tons NUMERIC,
    avg_fuel NUMERIC,
    downtime_count INT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.equipment_name::TEXT,
        SUM(fp.tons_mined),
        AVG(fp.fuel_consumed_l),
        (SELECT COUNT(*)::INT FROM fact_equipment_downtime fd WHERE fd.equipment_id = e.equipment_id)
    FROM dim_equipment e
    LEFT JOIN fact_production fp ON e.equipment_id = fp.equipment_id
    WHERE e.mine_id = p_mine_id
    GROUP BY e.equipment_id, e.equipment_name;
END;
$$;

SELECT * FROM get_equipment_summary(1);

--------------------------------------------------------------------------------
-- Задание 4. Хранимая процедура — архивация телеметрии
--------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS archive_telemetry (LIKE fact_equipment_telemetry INCLUDING ALL);

CREATE OR REPLACE PROCEDURE archive_old_telemetry(p_days_threshold INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    WITH deleted AS (
        DELETE FROM fact_equipment_telemetry
        WHERE timestamp < NOW() - (p_days_threshold || ' days')::INTERVAL
        RETURNING *
    )
    INSERT INTO archive_telemetry SELECT * FROM deleted;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Архивировано записей: %', v_deleted_count;
END;
$$;

CALL archive_old_telemetry(90);

--------------------------------------------------------------------------------
-- Задание 5. Процедура с транзакциями — загрузка дневной добычи
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE process_daily_production(p_date_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    -- 1. Валидация данных в staging
    IF EXISTS (SELECT 1 FROM staging_daily_production WHERE tons_mined < 0) THEN
        RAISE EXCEPTION 'Обнаружена отрицательная добыча!';
    END IF;
    
    COMMIT; -- Фиксируем проверку

    -- 2. Удаление старых данных за этот день
    DELETE FROM fact_production WHERE date_id = p_date_id;
    
    -- 3. Вставка новых данных
    INSERT INTO fact_production (date_id, equipment_id, operator_id, tons_mined)
    SELECT date_id, equipment_id, operator_id, tons_mined 
    FROM staging_daily_production
    WHERE date_id = p_date_id;

    RAISE NOTICE 'Данные за дату % успешно обновлены', p_date_id;
    
    -- Итоговая фиксация транзакции
    COMMIT;
END;
$$;


DROP FUNCTION IF EXISTS calc_oee(NUMERIC, NUMERIC, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS classify_downtime(INT);
DROP FUNCTION IF EXISTS get_equipment_summary(INT);
DROP PROCEDURE IF EXISTS archive_old_telemetry(INT);
DROP PROCEDURE IF EXISTS process_daily_production(INT);
