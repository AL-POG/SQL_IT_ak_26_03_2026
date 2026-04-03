-- Модуль 17: Применение обработки ошибок


--------------------------------------------------------------------------------
-- ПОДГОТОВКА: Таблица логов и вспомогательная функция
--------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS error_log (
    log_id      SERIAL PRIMARY KEY,
    log_time    TIMESTAMP DEFAULT NOW(),
    severity    VARCHAR(20),
    source      VARCHAR(100),
    sqlstate    VARCHAR(5),
    message     TEXT,
    detail      TEXT,
    hint        TEXT,
    context     TEXT,
    username    VARCHAR(100) DEFAULT CURRENT_USER,
    parameters  JSONB
);

CREATE OR REPLACE FUNCTION log_error(
    p_severity VARCHAR, 
    p_source VARCHAR,
    p_sqlstate VARCHAR DEFAULT NULL, 
    p_message TEXT DEFAULT NULL,
    p_detail TEXT DEFAULT NULL, 
    p_hint TEXT DEFAULT NULL,
    p_context TEXT DEFAULT NULL, 
    p_parameters JSONB DEFAULT NULL
)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE 
    v_log_id INT;
BEGIN
    INSERT INTO error_log (severity, source, sqlstate, message, detail, hint, context, parameters)
    VALUES (p_severity, p_source, p_sqlstate, p_message, p_detail, p_hint, p_context, p_parameters)
    RETURNING log_id INTO v_log_id;
    RETURN v_log_id;
END;
$$;

--------------------------------------------------------------------------------
-- Задание 1. Безопасное деление (Обработка DIVISION_BY_ZERO)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_safe_divide(p_numerator NUMERIC, p_denominator NUMERIC)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN
    RETURN p_numerator / p_denominator;
EXCEPTION 
    WHEN division_by_zero THEN
        PERFORM log_error(
            'WARNING', 
            'fn_safe_divide', 
            SQLSTATE, 
            'Попытка деления на ноль', 
            format('Числитель: %s, Знаменатель: %s', p_numerator, p_denominator)
        );
        RETURN NULL;
END;
$$;

SELECT fn_safe_divide(100, 0);

--------------------------------------------------------------------------------
-- Задание 2. Валидация качества руды (Пользовательские исключения)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_validate_ore_quality(p_fe NUMERIC, p_sio2 NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
    IF p_fe < 0 OR p_fe > 100 THEN
        RAISE EXCEPTION 'Некорректное содержание Fe: %', p_fe 
            USING ERRCODE = 'invalid_parameter_value',
                  HINT = 'Значение должно быть в диапазоне от 0 до 100';
    END IF;
    
    IF (p_fe + p_sio2) > 100 THEN
        RAISE EXCEPTION 'Сумма компонентов превышает 100%' 
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN TRUE;
EXCEPTION
    WHEN others THEN
        DECLARE
            v_msg TEXT;
            v_detail TEXT;
            v_hint TEXT;
        BEGIN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL, v_hint = PG_EXCEPTION_HINT;
            PERFORM log_error('ERROR', 'fn_validate_ore_quality', SQLSTATE, v_msg, v_detail, v_hint);
            RETURN FALSE;
        END;
END;
$$;

--------------------------------------------------------------------------------
-- Задание 3. Построчная обработка батча (Вложенные блоки)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pr_process_production_staging()
RETURNS TABLE(processed_rows INT, error_rows INT) LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
    v_proc_count INT := 0;
    v_err_count INT := 0;
BEGIN
    FOR r IN SELECT * FROM staging_production LOOP
        BEGIN
            -- Имитация вставки в основную таблицу
            INSERT INTO fact_production (date_id, tons_mined, equipment_id)
            VALUES (r.date_id, r.tons_mined, r.equipment_id);
            
            v_proc_count := v_proc_count + 1;
        EXCEPTION WHEN others THEN
            v_err_count := v_err_count + 1;
            PERFORM log_error(
                'ERROR', 
                'pr_process_production_staging', 
                SQLSTATE, 
                SQLERRM, 
                format('Row ID: %s', r.id),
                NULL,
                NULL,
                to_jsonb(r)
            );
        END;
    END LOOP;
    
    RETURN QUERY SELECT v_proc_count, v_err_count;
END;
$$;

--------------------------------------------------------------------------------
-- Задание 4. Комплексный KPI с UPSERT и защитой подблоков
--------------------------------------------------------------------------------

-- 1. Создание таблицы для результатов (если нет)
CREATE TABLE IF NOT EXISTS daily_kpi (
    mine_id     INT REFERENCES dim_mine(mine_id),
    date_id     INT,
    total_tons  NUMERIC,
    oee_score   NUMERIC,
    status      VARCHAR(20) DEFAULT 'OK',
    error_detail TEXT,
    updated_at  TIMESTAMP DEFAULT NOW(),
    UNIQUE (mine_id, date_id)
);

-- 2. Основная функция расчёта
CREATE OR REPLACE FUNCTION recalculate_daily_kpi(p_date_id INT)
RETURNS TABLE (mines_processed INT, mines_ok INT, mines_error INT) LANGUAGE plpgsql AS $$
DECLARE
    v_mine RECORD;
    v_total_tons NUMERIC;
    v_oee NUMERIC;
    v_processed INT := 0;
    v_ok INT := 0;
    v_error INT := 0;
BEGIN
    FOR v_mine IN SELECT mine_id, mine_name FROM dim_mine WHERE status = 'active' LOOP
        v_processed := v_processed + 1;
        
        BEGIN
            -- Блок расчётов
            SELECT SUM(tons_mined) INTO v_total_tons 
            FROM fact_production WHERE mine_id = v_mine.mine_id AND date_id = p_date_id;
            
            -- Пример расчета OEE с защитой от деления на ноль внутри блока
            SELECT (SUM(operating_hours) / NULLIF(SUM(planned_hours), 0)) * 100 INTO v_oee
            FROM fact_production WHERE mine_id = v_mine.mine_id AND date_id = p_date_id;

            -- UPSERT
            INSERT INTO daily_kpi (mine_id, date_id, total_tons, oee_score, status)
            VALUES (v_mine.mine_id, p_date_id, COALESCE(v_total_tons, 0), COALESCE(v_oee, 0), 'OK')
            ON CONFLICT (mine_id, date_id) DO UPDATE SET
                total_tons = EXCLUDED.total_tons,
                oee_score = EXCLUDED.oee_score,
                status = 'OK',
                error_detail = NULL,
                updated_at = NOW();
            
            v_ok := v_ok + 1;

        EXCEPTION WHEN others THEN
            v_error := v_error + 1;
            
            -- Записываем статус ошибки в саму таблицу KPI
            INSERT INTO daily_kpi (mine_id, date_id, status, error_detail)
            VALUES (v_mine.mine_id, p_date_id, 'ERROR', SQLERRM)
            ON CONFLICT (mine_id, date_id) DO UPDATE SET
                status = 'ERROR',
                error_detail = SQLERRM,
                updated_at = NOW();
                
            PERFORM log_error('CRITICAL', 'recalculate_daily_kpi', SQLSTATE, SQLERRM, format('Mine: %s', v_mine.mine_name));
        END;
    END LOOP;

    RETURN QUERY SELECT v_processed, v_ok, v_error;
END;
$$;

-- Тестирование:
SELECT * FROM recalculate_daily_kpi(20240315);
SELECT * FROM daily_kpi WHERE date_id = 20240315;
SELECT * FROM error_log ORDER BY log_id DESC;
