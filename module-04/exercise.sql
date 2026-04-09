-- =============================================================================
-- Module 4: Subqueries and CTEs
-- =============================================================================

.headers on
.mode column

-- -----------------------------------------------------------------------------
-- Q1. Each rider's first ride and the city it was in
-- -----------------------------------------------------------------------------
WITH first_ride AS (
  SELECT req.rider_id,
         MIN(r.started_at) AS first_started_at
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  GROUP BY req.rider_id
)
SELECT fr.rider_id,
       fr.first_started_at,
       c.name AS first_city
FROM   first_ride fr
JOIN   rides r ON r.started_at = fr.first_started_at
JOIN   requests req ON r.request_id = req.request_id
JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN   cities c ON n.city_id = c.city_id
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q2. For each driver, date and amount of their highest-fare ride
-- -----------------------------------------------------------------------------
WITH max_fare AS (
  SELECT driver_id, MAX(fare_usd) AS max_fare
  FROM   rides
  GROUP BY driver_id
)
SELECT r.driver_id,
       date(r.started_at) AS ride_date,
       r.fare_usd
FROM   rides r
JOIN   max_fare mf
  ON r.driver_id = mf.driver_id AND r.fare_usd = mf.max_fare
ORDER BY r.fare_usd DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q3. Riders active in each of the last 4 weeks of 2025
-- -----------------------------------------------------------------------------
WITH active AS (
  SELECT DISTINCT
    rider_id,
    strftime('%Y-%W', requested_at) AS week
  FROM   requests
  WHERE  date(requested_at) BETWEEN '2025-12-01' AND '2025-12-31'
)
SELECT rider_id, COUNT(DISTINCT week) AS weeks_active
FROM   active
GROUP BY rider_id
HAVING COUNT(DISTINCT week) >= 4
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q4. Multi-step funnel as CTE chain
-- -----------------------------------------------------------------------------
WITH dec_requests AS (
  SELECT request_id, rider_id, accepted
  FROM   requests
  WHERE  date(requested_at) BETWEEN '2025-12-01' AND '2025-12-31'
),
dec_rides AS (
  SELECT dr.request_id, dr.rider_id, r.ride_id, r.fare_usd, r.rider_rating
  FROM   dec_requests dr
  LEFT JOIN rides r ON dr.request_id = r.request_id
),
funnel AS (
  SELECT
    COUNT(*) AS n_requests,
    SUM(CASE WHEN ride_id IS NOT NULL THEN 1 ELSE 0 END) AS n_completed,
    SUM(CASE WHEN rider_rating = 5 THEN 1 ELSE 0 END)    AS n_5star
  FROM dec_rides
)
SELECT
  n_requests,
  n_completed,
  n_5star,
  ROUND(1.0 * n_completed / n_requests, 3) AS req_to_completed,
  ROUND(1.0 * n_5star / n_completed, 3)    AS completed_to_5star
FROM funnel;


-- -----------------------------------------------------------------------------
-- Q5. Cohort retention table (clean CTE version)
-- -----------------------------------------------------------------------------
WITH cohort AS (
  SELECT rider_id, strftime('%Y-%m', signup_date) AS cohort_month
  FROM   riders
),
activity AS (
  SELECT DISTINCT rider_id, strftime('%Y-%m', requested_at) AS activity_month
  FROM   requests
),
joined AS (
  SELECT c.rider_id, c.cohort_month, a.activity_month
  FROM   cohort c
  JOIN   activity a ON c.rider_id = a.rider_id
)
SELECT cohort_month,
       activity_month,
       COUNT(DISTINCT rider_id) AS active_riders
FROM   joined
GROUP BY cohort_month, activity_month
ORDER BY cohort_month, activity_month
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Q6. Recursive CTE: generate a calendar of weeks for joining
-- -----------------------------------------------------------------------------
WITH RECURSIVE weeks(week_start) AS (
  SELECT date('2025-01-06')
  UNION ALL
  SELECT date(week_start, '+7 days')
  FROM weeks
  WHERE week_start < date('2025-12-30')
)
SELECT week_start FROM weeks LIMIT 10;
