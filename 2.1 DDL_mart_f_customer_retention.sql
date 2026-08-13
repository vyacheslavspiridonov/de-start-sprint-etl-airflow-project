WITH orders AS (
	SELECT uniq_id
		, date_time
		, extract('week' from date_time) as period_id
		, 'weekly' as period_name
		, city_id
		, city_name
		, customer_id
		, first_name
		, last_name
		, item_id
		, item_name
		-- МЕТКА ВОЗВРАТА
		, CASE status WHEN 'shipped' THEN 0
				 	  WHEN 'refunded' THEN 1
				 	  ELSE NULL END AS refunded_mark
		-- УЧЁТ ВОЗВРАТОВ В СУММЕ ЗАКАЗА И КОЛИЧЕСТВЕ ТОВАРОВ ЗАКАЗА
		, CASE status WHEN 'shipped' THEN quantity
				 	  WHEN 'refunded' THEN (-1)*quantity
				 	  ELSE NULL END AS quantity
		, CASE status WHEN 'shipped' THEN payment_amount
				 	  WHEN 'refunded' THEN (-1)*payment_amount
				 	  ELSE NULL END AS payment_amount
		, status
		, MIN(date_time) OVER (PARTITION BY customer_id) as first_customer_order_date
	FROM staging.user_order_log uol
), 
  new_clients_classified AS (
	SELECT *,
		-- ЕСЛИ ДАТА И ВРЕМЯ ЗАКАЗА РАВНА ПЕРВОЙ (МИНИМАЛЬНОЙ) ДАТЕ И ВРЕМЕНИ ЗАКАЗА КЛИЕНТА, ТО КЛИЕНТ НОВЫЙ 
		-- (И ЕСЛИ ЭТО НЕ ВОЗВРАТ [AND payment_amount > 0] - ОБРАТНЫЙ СЛУЧАЙ [AND payment_amount < 0]
		-- ОЗНАЧАЕТ, ЧТО ПРЕЖНЯЯ ПОКУПКА КЛИЕНТА НЕ ПОПАЛА В ДАННЫЕ, НО БЫЛА - Т.К. ВОЗВРАТА БЕЗ ПОКУПКИ НЕ БЫВАЕТ)
		CASE WHEN first_customer_order_date = date_time AND payment_amount > 0 THEN 'Новый клиент (Первая покупка)'
			 ELSE '-' -- 'Вернувшийся клиент (Были покупки)' 
			 END AS client_type 
	FROM orders
),
  new_clients_periods AS (
  	-- ВЫБИРАЕМ ПЕРИОДЫ, В РАМКАХ КОТОРЫХ КЛИЕНТ БУДЕТ СЧИТАТЬСЯ НОВЫМ (ПО ПЕРИОДУ[НЕДЕЛЕ] ПЕРВОЙ ПОКУПКИ)
    -- Т.Е. ДОПУСКАЕМ, ЧТО КЛИЕНТ ОСТАЁТСЯ НОВЫМ ДО КОНЦА ОТЧЁТНОГО ПЕРИОДА[НЕДЕЛИ]
	SELECT distinct period_id, customer_id, client_type
	FROM new_clients_classified
	WHERE client_type = 'Новый клиент (Первая покупка)'
),
  old_clients_classified AS (
	SELECT o.*
		-- В ОСТАЛЬНЫХ СЛУЧАЯХ КЛИЕНТ СЧИТАЕТСЯ ВЕРНУВШИМСЯ
		, COALESCE(ncp.client_type, 'Вернувшийся клиент (Были покупки)') as client_type
		, CASE WHEN ncp.client_type IS NULL THEN 0
			   ELSE 1 END AS new_client_mark
	FROM orders o
		LEFT JOIN new_clients_periods ncp on o.period_id = ncp.period_id and o.customer_id = ncp.customer_id
)
SELECT 
	-- В РАЗРЕЗЕ ПЕРИОДА И КАТЕГОРИИ ТОВАРА
	period_id,
	period_name,
	item_id,
	-- РАССЧИТЫВАЕМ НЕОБХОДИМЫЕ ПОКАЗАТЕЛИ
	SUM(payment_amount) FILTER (WHERE new_client_mark = 1) AS "Доход новых Клиентов",
	SUM(payment_amount) FILTER (WHERE new_client_mark = 0) AS "Доход вернувшихся Клиентов",
	COUNT(distinct customer_id) FILTER (WHERE new_client_mark = 1) AS "Количество новых клиентов",
	COUNT(distinct customer_id) FILTER (WHERE new_client_mark = 0) AS "Количество вернувшихся клиентов",
	COUNT(distinct customer_id) FILTER (WHERE refunded_mark = 1) 	 AS "Количество клиентов с возвратами",
	SUM(refunded_mark) AS "Количество возвратов"
FROM old_clients_classified
GROUP BY
	period_id,
	period_name,
	item_id
	-- СОРТИРОВКА ДЛЯ БОЛЬШЕЙ ЧИТАЕМОСТИ РЕЗУЛЬТАТА
ORDER BY period_id, item_id;

