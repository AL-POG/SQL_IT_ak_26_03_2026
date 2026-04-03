
-- Модуль 5: Использование DML для изменения данных

BEGIN;

--------------------------------------------------------------------------------
-- Задание 1. Добавление нового оборудования (одна строка)
--------------------------------------------------------------------------------
-- Проверка: SELECT * FROM practice_dim_equipment WHERE equipment_id = 200;

INSERT INTO practice_dim_equipment (
    equipment_id, equipment_type_id, mine_id, equipment_name, 
    inventory_number, manufacturer, model, year_manufactured, 
    commissioning_date, status, has_video_recorder, has_navigation
) VALUES (
    200, 2, 2, 'Самосвал МоАЗ-7529', 
    'INV-TRK-200', 'МоАЗ', '7529', 2025, 
    '2025-03-15', 'active', TRUE, TRUE
);

--------------------------------------------------------------------------------
-- Задание 2. Массовая вставка операторов (несколько строк)
--------------------------------------------------------------------------------
INSERT INTO practice_dim_operator (
    operator_id, tab_number, last_name, first_name, middle_name, 
    position, qualification, hire_date, mine_id
) VALUES 
(200, 'TAB-200', 'Сидоров', 'Михаил', 'Иванович', 'Машинист ПДМ', '4 разряд', '2025-03-01', 1),
(201, 'TAB-201', 'Петрова', 'Елена', 'Сергеевна', 'Оператор скипа', '3 разряд', '2025-03-01', 2),
(202, 'TAB-202', 'Волков', 'Дмитрий', 'Алексеевич', 'Водитель самосвала', '5 разряд', '2025-03-10', 2);

--------------------------------------------------------------------------------
-- Задание 3. Загрузка из staging (INSERT ... SELECT)
--------------------------------------------------------------------------------
INSERT INTO practice_fact_production (
    production_id, date_id, shift_id, equipment_id, 
    operator_id, ore_grade_id, weight_netto
)
SELECT 
    3000 + staging_id, date_id, shift_id, equipment_id, 
    operator_id, ore_grade_id, weight_netto
FROM staging_production s
WHERE is_validated = TRUE
  AND NOT EXISTS (
      SELECT 1 FROM practice_fact_production p
      WHERE p.date_id = s.date_id 
        AND p.shift_id = s.shift_id 
        AND p.equipment_id = s.equipment_id 
        AND p.operator_id = s.operator_id
  );

--------------------------------------------------------------------------------
-- Задание 4. INSERT ... RETURNING с логированием
--------------------------------------------------------------------------------
WITH new_grade AS (
    INSERT INTO practice_dim_ore_grade (
        ore_grade_id, grade_name, grade_code, 
        fe_content_min, fe_content_max, description
    ) VALUES (
        300, 'Экспортный', 'EXPORT', 63.00, 68.00, 'Руда для экспортных поставок'
    )
    RETURNING ore_grade_id, grade_name, grade_code
)
INSERT INTO practice_equipment_log (equipment_id, action, details)
SELECT 0, 'INSERT', 'Добавлен сорт руды: ' || grade_name || ' (' || grade_code || ')'
FROM new_grade;

--------------------------------------------------------------------------------
-- Задание 5. Обновление статуса оборудования (UPDATE)
--------------------------------------------------------------------------------
UPDATE practice_dim_equipment
SET status = 'maintenance'
WHERE mine_id = 1 AND year_manufactured <= 2018
RETURNING equipment_id, equipment_name, year_manufactured;

--------------------------------------------------------------------------------
-- Задание 6. UPDATE с подзапросом
--------------------------------------------------------------------------------
UPDATE practice_dim_equipment
SET has_navigation = TRUE
WHERE has_navigation = FALSE
  AND equipment_id IN (
      SELECT s.equipment_id
      FROM dim_sensor s
      JOIN dim_sensor_type st ON s.sensor_type_id = st.sensor_type_id
      WHERE st.sensor_type_code = 'NAV' -- Предполагаемый код для типа 'NAV'
  );

--------------------------------------------------------------------------------
-- Задание 7. DELETE с условием и архивированием
--------------------------------------------------------------------------------
WITH deleted_telemetry AS (
    DELETE FROM practice_fact_telemetry
    WHERE is_alarm = TRUE AND date_id = 20240315
    RETURNING *
)
INSERT INTO practice_archive_telemetry (
    telemetry_id, date_id, equipment_id, sensor_id, 
    sensor_value, is_alarm, quality_flag, archived_at
)
SELECT *, CURRENT_TIMESTAMP FROM deleted_telemetry;

--------------------------------------------------------------------------------
-- Задание 8. MERGE — синхронизация справочника (PostgreSQL 15+)
--------------------------------------------------------------------------------
MERGE INTO practice_dim_downtime_reason AS target
USING staging_downtime_reasons AS source
ON target.reason_code = source.reason_code
WHEN MATCHED THEN
    UPDATE SET 
        reason_name = source.reason_name,
        category = source.category,
        description = source.description
WHEN NOT MATCHED THEN
    INSERT (reason_id, reason_name, reason_code, category, description)
    VALUES (
        (SELECT COALESCE(MAX(reason_id), 0) + 1 FROM practice_dim_downtime_reason), 
        source.reason_name, source.reason_code, source.category, source.description
    );

--------------------------------------------------------------------------------
-- Задание 9. UPSERT (INSERT ... ON CONFLICT)
--------------------------------------------------------------------------------
INSERT INTO practice_dim_operator (
    operator_id, tab_number, last_name, first_name, middle_name, 
    position, qualification, hire_date, mine_id
) VALUES 
(200, 'TAB-200', 'Сидоров', 'Михаил', 'Иванович', 'Машинист ПДМ (Обновлено)', '5 разряд', '2025-03-01', 1),
(201, 'TAB-201', 'Петрова', 'Елена', 'Сергеевна', 'Старший оператор', '4 разряд', '2025-03-01', 2),
(205, 'TAB-NEW', 'Новиков', 'Игорь', 'Петрович', 'Техник', '2 разряд', CURRENT_DATE, 1)
ON CONFLICT (tab_number) DO UPDATE SET
    position = EXCLUDED.position,
    qualification = EXCLUDED.qualification;



COMMIT;
