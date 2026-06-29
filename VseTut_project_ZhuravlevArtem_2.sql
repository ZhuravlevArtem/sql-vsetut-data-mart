 /* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Журавлев Артем
 * Дата: 21.10.2025
*/



/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/
-- Витрина product_user_features с агрегированными характеристиками поведения пользователей
-- Фильтрация: только доставленные/отмененные заказы, топ-3 региона по активности

WITH
-- 1) три региона с максимальным числом доставленных/отменённых заказов
top_regions AS (
    SELECT u.region
    FROM ds_ecom.orders o
    JOIN ds_ecom.users u ON o.buyer_id = u.buyer_id
    WHERE o.order_status IN ('Доставлено','Отменено')
    GROUP BY u.region
    ORDER BY COUNT(*) DESC
    LIMIT 3
),

-- 2) первый тип оплаты, промокод и рассрочка по заказу
first_payment_type_per_order AS (
    SELECT 
        op.order_id,
        MAX(CASE WHEN op.payment_sequential = 1 THEN op.payment_type END) AS first_payment_type,
        MAX(CASE WHEN op.payment_type = 'промокод' THEN 1 ELSE 0 END) AS used_promocode,
        MAX(CASE WHEN op.payment_installments > 1 THEN 1 ELSE 0 END) AS is_installments_order
    FROM ds_ecom.order_payments op
    GROUP BY op.order_id
),

-- 3) стоимость заказов
order_costs AS (
    SELECT
        o.order_id,
        SUM(oi.price + oi.delivery_cost) AS order_cost
    FROM ds_ecom.orders o
    JOIN ds_ecom.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'Доставлено'
    GROUP BY o.order_id
),

-- 4) средний рейтинг заказа с учётом разных шкал
order_rating AS (
    SELECT
        r.order_id,
        AVG(
            r.review_score / 
            CASE 
                WHEN r.review_score BETWEEN 10 AND 50 THEN 10.0
                ELSE 1.0
            END
        ) AS order_rating
    FROM ds_ecom.order_reviews r
    GROUP BY r.order_id
),

-- 5) предварительная фильтрация заказов: только топ‑3 региона + нужные статусы
orders_pre_filtered AS (
    SELECT
        o.order_id,
        u.user_id,
        u.region,
        o.order_status,
        o.order_purchase_ts
    FROM ds_ecom.orders o
    JOIN ds_ecom.users u ON o.buyer_id = u.buyer_id
    WHERE o.order_status IN ('Доставлено','Отменено')
      AND u.region IN (SELECT region FROM top_regions)
),

-- 6) присоединяем стоимость, рейтинг и платежи
orders_filtered AS (
    SELECT
        opf.order_id,
        opf.user_id,
        opf.region,
        opf.order_status,
        opf.order_purchase_ts,
        fpt.first_payment_type,
        fpt.used_promocode,
        fpt.is_installments_order,
        oc.order_cost,
        orr.order_rating
    FROM orders_pre_filtered opf
    LEFT JOIN first_payment_type_per_order fpt ON opf.order_id = fpt.order_id
    LEFT JOIN order_costs oc ON opf.order_id = oc.order_id
    LEFT JOIN order_rating orr ON opf.order_id = orr.order_id
),

-- 7) агрегируем по пользователю и региону
user_order_stat AS (
    SELECT
        user_id,
        region,
        MIN(order_purchase_ts) AS first_order_ts,
        MAX(order_purchase_ts) AS last_order_ts,
        MAX(order_purchase_ts) - MIN(order_purchase_ts) AS lifetime,
        COUNT(*) AS total_orders,
        AVG(order_rating) AS avg_order_rating,
        COUNT(order_rating) AS num_orders_with_rating,
        
        COUNT(CASE WHEN order_status = 'Отменено' THEN 1 END) AS num_canceled_orders,
        ROUND(COUNT(CASE WHEN order_status = 'Отменено' THEN 1 END) * 1.0 / COUNT(*), 4) AS canceled_orders_ratio,
        
        SUM(CASE WHEN order_status = 'Доставлено' THEN order_cost END) AS total_order_costs,
        ROUND(AVG(CASE WHEN order_status = 'Доставлено' THEN order_cost END), 2) AS avg_order_cost,
    
        COUNT(CASE WHEN is_installments_order = 1 THEN 1 END) AS num_installment_orders,
        COUNT(CASE WHEN used_promocode = 1 THEN 1 END) AS num_orders_with_promo,

        MAX(CASE WHEN first_payment_type = 'денежный перевод' THEN 1 ELSE 0 END) AS used_money_transfer,
        MAX(is_installments_order) AS used_installments,
        MAX(CASE WHEN order_status = 'Отменено' THEN 1 ELSE 0 END) AS used_cancel
        
    FROM orders_filtered
    GROUP BY user_id, region
)

-- ФИНАЛЬНЫЙ SELECT 
SELECT *
FROM user_order_stat;

/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Напишите ваш запрос тут
/* Задача 1. Сегментация пользователей */
WITH user_segments AS (
    SELECT 
        user_id,
        total_orders,
        avg_order_cost,
        total_order_costs, -- Добавил для корректного расчета среднего значения
        CASE 
            WHEN total_orders = 1 THEN '1 заказ'
            WHEN total_orders BETWEEN 2 AND 5 THEN '2-5 заказов'
            WHEN total_orders BETWEEN 6 AND 10 THEN '6-10 заказов'
            ELSE '11 и более заказов'
        END AS segment
    FROM ds_ecom.product_user_features
)
SELECT 
    segment AS сегмент,
    COUNT(DISTINCT user_id) AS количество_пользователей,
    ROUND(AVG(total_orders), 2) AS среднее_количество_заказов,
    ROUND(SUM(total_order_costs) / NULLIF(SUM(total_orders), 0), 2) AS средняя_стоимость_заказа -
    SUM(total_orders) AS общее_количество_заказов
FROM user_segments
GROUP BY segment
ORDER BY segment; 
/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * 
 1. 96% клиентов совершили всего 1 заказ - есть огромный потенциал роста
 2. Всего 6 человек сделали 6+ заказов - очень мало постоянных клиентов
 3. Чем больше заказов - тем меньше средний чек:
        1 заказ: 3,324 руб.
        11+ заказов: 1,245 руб. (в 2.5 раза меньше)
*/



/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Напишите ваш запрос тут
SELECT 
    user_id,
    region,
    total_orders AS количество_заказов,
    ROUND(avg_order_cost, 2) AS средний_чек,
    ROUND(total_order_costs, 2) AS общая_стоимость_заказов
    FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15;
/* Напишите краткий комментарий с выводами по результатам задачи 2.
 * 1. Москва и Питер лидируют - 11 из 15 топ-клиентов из этих городов
   2. 14 из 15 клиентов сделали ровно 3 заказа
   3. В основном довольны сервисом - у большинства высокие оценки (4-5 баллов)

*/



/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Напишите ваш запрос тут
SELECT 
    region AS регион,
    COUNT(DISTINCT user_id) AS общее_число_клиентов,
    SUM(total_orders) AS всего_заказов,
    ROUND(SUM(total_order_costs) / NULLIF(SUM(total_orders), 0), 2) AS средняя_стоимость_заказа,
    ROUND(SUM(num_installment_orders) * 100.0 / NULLIF(SUM(total_orders), 0), 2) AS доля_заказов_в_рассрочку_проценты,
    ROUND(SUM(num_orders_with_promo) * 100.0 / NULLIF(SUM(total_orders), 0), 2) AS доля_заказов_с_промокодами_проценты,
    ROUND(SUM(used_cancel) * 100.0 / COUNT(DISTINCT user_id), 2) AS доля_пользователей_с_отменами_проценты
FROM ds_ecom.product_user_features
GROUP BY region
ORDER BY общее_число_клиентов DESC;
/* Напишите краткий комментарий с выводами по результатам задачи 3.
 * 1. Москва - главный рынок: 39K клиентов (63% от всех)
   2. Самые платежеспособные в Питере: средний чек 3,620 руб.
   3. Рассрочка очень популярна: больше половины заказов во всех регионах
   4. Промокоды почти не используют: всего 3-4% заказов
   5. Новосибирск - самый надежный: меньше всего отмен заказов
*/



/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

-- Напишите ваш запрос тут
SELECT 
    TO_CHAR(first_order_ts, 'YYYY-MM') AS месяц_первого_заказа,
    COUNT(DISTINCT user_id) AS количество_клиентов,
    SUM(total_orders) AS число_заказов,
    ROUND(AVG(avg_order_cost), 2) AS средняя_стоимость_заказа,
    ROUND(AVG(avg_order_rating), 2) AS средний_рейтинг_заказа,
    ROUND(SUM(used_money_transfer) * 100.0 / COUNT(DISTINCT user_id), 2) AS доля_денежных_переводов_проценты,
    ROUND(AVG(EXTRACT(EPOCH FROM lifetime) / 86400), 2) AS средняя_продолжительность_активности_дни
FROM ds_ecom.product_user_features
WHERE EXTRACT(YEAR FROM first_order_ts) = 2023
GROUP BY TO_CHAR(first_order_ts, 'YYYY-MM')
ORDER BY месяц_первого_заказа;
/* Напишите краткий комментарий с выводами по результатам задачи 4.
 * 1. Ноябрь - рекорд по новичкам: 4,703 клиента (в 10 раз больше чем в январе)
   2. Осенью самые дорогие покупки: сентябрь-октябрь лидеры по среднему чеку
   3. Чем позже пришли - тем меньше активны:
        Январь: 13 дней активности
        Декабрь: всего 2 дня
   4. Денежные переводы популярны: 20-22% клиентов используют
   5. Рейтинги стабильно высокие: 4.0-4.3 балла весь год


   