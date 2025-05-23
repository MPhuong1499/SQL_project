---1
WITH cte AS(
SELECT *,
CASE WHEN (order_date = customer_pref_delivery_date ) THEN 'immediate'
    ELSE 'scheduled'
    END AS type,
FIRST_VALUE (order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS earliest_order
FROM Delivery
)
SELECT
ROUND(100.0*COUNT (*) / (SELECT COUNT(DISTINCT customer_id) FROM Delivery),2) AS immediate_percentage
FROM cte
WHERE order_date = earliest_order AND type = 'immediate';

---other approach from discussion
select ROUND (100.0 * sum(CASE WHEN order_date=customer_pref_delivery_date THEN 1 ELSE 0 END) / count(*) , 2) as immediate_percentage 
from Delivery 
where (customer_id, order_date) in (select customer_id, min(order_date) from Delivery group by customer_id);

---2
WITH cte AS(
SELECT *,
RANK () OVER (PARTITION BY player_id  ORDER BY event_date) AS day_rank,
LEAD(event_date) OVER (PARTITION BY player_id  ORDER BY event_date) - event_date AS diff
FROM Activity
)
SELECT ROUND(COUNT (*)::NUMERIC / (SELECT COUNT(DISTINCT player_id) FROM Activity),2) AS fraction
FROM cte
WHERE day_rank = 1 AND diff = 1

---other approach
SELECT ROUND(
    1.0 * COUNT(player_id) / 
    (SELECT COUNT(DISTINCT player_id)
    FROM Activity), 2) AS fraction
FROM Activity
WHERE (player_id, event_date) IN (
    SELECT player_id, MIN(event_date) + 1
    FROM Activity
    GROUP BY player_id
)

---3
SELECT 
s1.id,
    CASE 
        WHEN MOD(s1.id, 2) = 0 THEN (SELECT student FROM seat s2 WHERE s2.id = s1.id-1)
        WHEN s1.id = (SELECT MAX(id) FROM seat) AND MOD(s1.id, 2) = 1 THEN student
        ELSE (SELECT student FROM seat s3 WHERE s3.id = s1.id+1)
    END AS student
FROM seat s1

---other approach
SELECT 
id,
    CASE 
        WHEN MOD(id, 2) = 0 THEN LAG(student) OVER (ORDER BY id)
        WHEN id = (SELECT MAX(id) FROM seat) AND MOD(id, 2) = 1 THEN student
        ELSE LEAD(student) OVER (ORDER BY id)
    END AS student
FROM seat 

---from discussion
SELECT(
  CASE WHEN id % 2 = 1 and  id = (select max(id) from Seat) THEN id
  WHEN id % 2 = 1 THEN id + 1
  WHEN id % 2 = 0 THEN id - 1
  END ) AS id, student 
FROM Seat
ORDER BY id

---4
WITH cte1 AS(
WITH cte AS(
SELECT
visited_on,
SUM(amount) AS total_amount
FROM Customer
GROUP BY visited_on
)
SELECT 
visited_on,
SUM(total_amount) OVER (ORDER BY visited_on ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS amount,
ROUND(AVG(total_amount) OVER (ORDER BY visited_on ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),2) AS average_amount,
RANK () OVER (ORDER BY visited_on) AS ranking
FROM cte
)
SELECT
visited_on, amount, average_amount
FROM cte1 
WHERE ranking > 6;

---from discussion
WITH last_6_days AS (
    SELECT DISTINCT visited_on
    FROM Customer
    ORDER BY visited_on ASC
    OFFSET 6
)

SELECT c1.visited_on,
        SUM(c2.amount) AS amount,
        ROUND(SUM(c2.amount) / 7., 2)  AS average_amount
FROM last_6_days AS c1
INNER JOIN Customer AS c2
ON c2.visited_on BETWEEN c1.visited_on - 6 AND c1.visited_on
GROUP BY c1.visited_on;
    
---5
SELECT ROUND(SUM(tiv_2016)::NUMERIC,2) AS tiv_2016
FROM Insurance
WHERE pid IN (
(SELECT
DISTINCT i1.pid
FROM Insurance i1
JOIN Insurance i2
ON i1.tiv_2015 = i2.tiv_2015
AND i1.pid <> i2.pid)
EXCEPT
(SELECT DISTINCT i1.pid
FROM Insurance i1
JOIN Insurance i2
ON i1.lat = i2.lat
AND i1.lon = i2.lon
AND i1.pid <> i2.pid)
)

---from dícussion
SELECT ROUND(SUM(tiv_2016)::NUMERIC,2) AS tiv_2016 FROM Insurance 
WHERE (tiv_2015) IN (SELECT tiv_2015 FROM Insurance GROUP BY tiv_2015 HAVING COUNT(*) > 1) AND
(lat, lon) IN (SELECT lat, lon FROM Insurance GROUP BY lat,lon HAVING count(*) = 1)

---other approach
WITH counts AS (
    SELECT 
        pid,
        tiv_2015,
        tiv_2016,
        lat,
        lon,
        COUNT(*) OVER (PARTITION BY tiv_2015) AS tiv_2015_count,
        COUNT(*) OVER (PARTITION BY lat, lon) AS location_count
    FROM Insurance
)
SELECT 
    ROUND(SUM(tiv_2016), 2) AS tiv_2016
FROM counts
WHERE 
    tiv_2015_count > 1  -- Same tiv_2015 as another policyholder
    AND location_count = 1;  -- Unique (lat, lon) pair

---6
WITH cte AS (
SELECT d.name AS Department, e.name AS Employee, e.salary AS Salary,
DENSE_RANK () OVER (PARTITION BY d.name ORDER BY e.salary DESC) AS ranking
FROM Employee e
JOIN Department d
ON e.departmentId = d.id
)
SELECT Department, Employee, Salary FROM cte
WHERE ranking <=3

---7
WITH cte AS(
SELECT *,
SUM(weight) OVER (ORDER BY turn ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
FROM Queue
)
SELECT person_name FROM cte
WHERE turn = (SELECT MAX(turn) FROM cte WHERE sum <= 1000)

---8
WITH price_on_date AS (
    SELECT 
        product_id,
        new_price,
        change_date,
        FIRST_VALUE(new_price) OVER (
            PARTITION BY product_id
            ORDER BY change_date DESC
        ) AS latest_price
    FROM Products
    WHERE change_date <= '2019-08-16'
),
distinct_products AS (
    SELECT DISTINCT product_id
    FROM Products
)
SELECT 
    dp.product_id,
    COALESCE(pod.latest_price, 10) AS price
FROM distinct_products dp
LEFT JOIN price_on_date pod
    ON dp.product_id = pod.product_id
    AND pod.change_date = (
        SELECT MAX(change_date)
        FROM Products p
        WHERE p.product_id = dp.product_id
        AND p.change_date <= '2019-08-16'
    )
ORDER BY dp.product_id;

---other approach
select
    distinct product_id,
    10 as price
from
    Products
group by
    product_id
having
    min(change_date) > '2019-08-16'

union

select
    product_id,
    new_price as price
from
    Products
where
    (product_id, change_date) in (
        select
            product_id,
            max(change_date)
        from
            Products
        where
            change_date <= '2019-08-16'
        group by
            product_id
        )




