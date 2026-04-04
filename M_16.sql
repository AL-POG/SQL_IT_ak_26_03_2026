


-- Модуль 16: Программирование при помощи SQL


--------------------------------------------------------------------------------
-- Задание 1. Анонимный блок — статистика по шахтам
--------------------------------------------------------------------------------
-- Получить сводку показателей через RAISE NOTICE
DO $$
DECLARE
    v_mine_count    INT;
    v_total_tons    NUMERIC;
    v_avg_fe        NUMERIC;
    v_downtime_count INT;
BEGIN
    -- Сбор данных в переменные
    SELECT COUNT(*) INTO v_mine_count FROM dim_mine;
    
    SELECT SUM(tons_mined) INTO v_total_tons 
    FROM fact_production 
    WHERE date_id BETWEEN 20250101 AND 20250131;
    
    SELECT ROUND(AVG(fe_content), 2) INTO v_avg_fe 
    FROM fact_ore_quality 
    WHERE date_id BETWEEN 20250101 AND 20250131;
    
    SELECT COUNT(*) INTO v_downtime_count 
    FROM fact_equipment_downtime 
    WHERE date_id BETWEEN 20250101 AND 20250131;

    -- Вывод отчета
    RAISE NOTICE '===== Сводка по предприятию «Руда+» =====';
    RAISE NOTICE 'Количество шахт: %', v_mine_count;
    RAISE NOTICE 'Добыча за январь 2025: % т', COALESCE(v_total_tons, 0);
    RAISE NOTICE 'Среднее содержание Fe: % %%', COALESCE(v_avg_fe, 0);
    RAISE NOTICE 'Количество простоев: %', v_downtime_count;
    RAISE NOTICE '==========================================';
END $$;

--------------------------------------------------------------------------------
-- Задание 2. Переменные и классификация — категории оборудования
--------------------------------------------------------------------------------
-- Категоризация техники по году выпуска с использованием IF/CASE
DO $$
DECLARE
    v_equip_rec RECORD;
    v_age       INT;
    v_category  TEXT;
BEGIN
    RAISE NOTICE 'Анализ парка оборудования:';
    
    FOR v_equip_rec IN (SELECT equipment_name, year_manufactured FROM dim_equipment LIMIT 10) LOOP
        v_age := EXTRACT(YEAR FROM CURRENT_DATE) - v_equip_rec.year_manufactured;
        
        -- Условная логика
        IF v_age <= 3 THEN
            v_category := 'Новое';
        ELSIF v_age BETWEEN 4 AND 7 THEN
            v_category := 'Средний износ';
        ELSE
            v_category := 'Требует замены';
        END IF;
        
        RAISE NOTICE 'Машина: % | Возраст: % лет | Категория: %', 
                     RPAD(v_equip_rec.equipment_name, 20), 
                     v_age, 
                     v_category;
    END LOOP;
END $$;

--------------------------------------------------------------------------------
-- Задание 3. Подневной анализ — цикл по датам
--------------------------------------------------------------------------------
-- Пройтись циклом по первой неделе января и вывести итоги
DO $$
DECLARE
    v_date_cursor DATE := '2025-01-01';
    v_daily_tons  NUMERIC;
BEGIN
    RAISE NOTICE 'Оперативный отчет за первую неделю января:';
    
    WHILE v_date_cursor <= '2025-01-07' LOOP
        -- Получаем добычу за конкретный день
        SELECT SUM(tons_mined) INTO v_daily_tons 
        FROM fact_production fp
        JOIN dim_date d ON fp.date_id = d.date_id
        WHERE d.full_date = v_date_cursor;
        
        RAISE NOTICE 'Дата: % | Добыча: % тонн', 
                     v_date_cursor, 
                     COALESCE(v_daily_tons, 0);
        
        -- Инкремент даты
        v_date_cursor := v_date_cursor + INTERVAL '1 day';
    END LOOP;
END $$;
