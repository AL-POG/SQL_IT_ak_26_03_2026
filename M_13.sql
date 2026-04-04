-- Модуль 13: Использование оконных функций

--------------------------------------------------------------------------------
-- Задание 1. Доля оборудования в общей добыче (Агрегация OVER)
--------------------------------------------------------------------------------
-- Посчитать % вклада каждой машины в общую добычу смены
SELECT 
    e.equipment_name,
    fp.tons_mined,
    SUM(fp.tons_mined) OVER() AS total_shift_tons,
    ROUND(fp.tons_mined * 100.0 / SUM(fp.tons_mined) OVER(), 1) AS pct_of_total
FROM fact_production fp
JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
WHERE fp.date_id = 20240115 AND fp.shift_id = 1
ORDER BY fp.tons_mined DESC;

--------------------------------------------------------------------------------
-- Задание 2. Нарастающий итог по шахтам (PARTITION BY)
--------------------------------------------------------------------------------
-- Посмотреть, как копится добыча внутри каждой шахты день за днем
SELECT 
    m.mine_name,
    d.full_date,
    SUM(fp.tons_mined) AS daily_tons,
    SUM(SUM(fp.tons_mined)) OVER(
        PARTITION BY m.mine_id 
        ORDER BY d.full_date
    ) AS cumulative_tons
FROM fact_production fp
JOIN dim_mine m ON fp.mine_id = m.mine_id
JOIN dim_date d ON fp.date_id = d.date_id
GROUP BY m.mine_id, m.mine_name, d.full_date
ORDER BY m.mine_name, d.full_date;

--------------------------------------------------------------------------------
-- Задание 3. Скользящее среднее содержания Fe
--------------------------------------------------------------------------------
-- Сгладить ежедневные колебания качества руды за 3 дня
WITH DailyQuality AS (
    SELECT 
        d.full_date, 
        AVG(fq.fe_content) AS avg_fe
    FROM fact_ore_quality fq
    JOIN dim_date d ON fq.date_id = d.date_id
    GROUP BY d.full_date
)
SELECT 
    full_date,
    ROUND(avg_fe, 2) AS daily_fe,
    ROUND(AVG(avg_fe) OVER(
        ORDER BY full_date 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3d
FROM DailyQuality;

--------------------------------------------------------------------------------
-- Задание 4. Ранжирование оборудования
--------------------------------------------------------------------------------
-- Составить рейтинг машин по производительности
SELECT 
    equipment_name,
    total_tons,
    RANK() OVER(ORDER BY total_tons DESC) AS p_rank, -- Пропускает номера при совпадении
    DENSE_RANK() OVER(ORDER BY total_tons DESC) AS p_dense -- Не пропускает номера
FROM (
    SELECT e.equipment_name, SUM(fp.tons_mined) AS total_tons
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    GROUP BY e.equipment_name
) sub;

--------------------------------------------------------------------------------
-- Задание 5. Сравнение с предыдущим днем
--------------------------------------------------------------------------------
-- Рассчитать динамику добычи (прирост/падение)
WITH DailyProd AS (
    SELECT d.full_date, SUM(fp.tons_mined) AS tons
    FROM fact_production fp
    JOIN dim_date d ON fp.date_id = d.date_id
    GROUP BY d.full_date
)
SELECT 
    full_date,
    tons AS current_day,
    LAG(tons) OVER(ORDER BY full_date) AS prev_day,
    tons - LAG(tons) OVER(ORDER BY full_date) AS delta
FROM DailyProd;

--------------------------------------------------------------------------------
-- Задание 6. Деление на группы
--------------------------------------------------------------------------------
-- Разбить смены на 4 квартиля по объему добычи
SELECT 
    date_id,
    shift_id,
    SUM(tons_mined) AS total_tons,
    NTILE(4) OVER(ORDER BY SUM(tons_mined) DESC) AS performance_quartile
FROM fact_production
GROUP BY date_id, shift_id;






