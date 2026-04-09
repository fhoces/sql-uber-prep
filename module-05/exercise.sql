-- =============================================================================
-- Module 5: Window Functions
-- =============================================================================

.headers on
.mode column

-- -----------------------------------------------------------------------------
-- Q1. Rank drivers within each city by total earnings
-- -----------------------------------------------------------------------------
WITH driver_city_earnings AS (
  SELECT r.driver_id,
         n.city_id,
         SUM(r.fare_usd) AS total_earnings
  FROM rides r
  JOIN requests req ON r.request_id = req.request_id
  JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  GROUP BY r.driver_id, n.city_id
)
SELECT
  city_id,
  driver_id,
  ROUND(total_earnings, 2) AS total_earnings,
  RANK() OVER (PARTITION BY city_id ORDER BY total_earnings DESC) AS city_rank
FROM driver_city_earnings
ORDER BY city_id, city_rank
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q2. For each ride, compute the time since the driver's previous ride
-- -----------------------------------------------------------------------------
SELECT
  ride_id,
  driver_id,
  started_at,
  LAG(started_at, 1) OVER (PARTITION BY driver_id ORDER BY started_at) AS prev_ride,
  ROUND(
    (julianday(started_at) -
     julianday(LAG(started_at, 1) OVER (PARTITION BY driver_id ORDER BY started_at))
    ) * 24, 2
  ) AS hours_since_last
FROM rides
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Q3. 7-day rolling average of daily ride counts per city
-- -----------------------------------------------------------------------------
WITH daily AS (
  SELECT
    n.city_id,
    date(r.started_at) AS day,
    COUNT(*) AS rides_today
  FROM rides r
  JOIN requests req ON r.request_id = req.request_id
  JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  GROUP BY n.city_id, day
)
SELECT
  city_id,
  day,
  rides_today,
  ROUND(AVG(rides_today) OVER (
    PARTITION BY city_id
    ORDER BY day
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ), 1) AS rolling_7d_avg
FROM daily
ORDER BY city_id, day
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Q4. Top fare ride per driver (ROW_NUMBER pattern)
-- -----------------------------------------------------------------------------
WITH ranked AS (
  SELECT
    driver_id,
    ride_id,
    fare_usd,
    started_at,
    ROW_NUMBER() OVER (PARTITION BY driver_id ORDER BY fare_usd DESC) AS rk
  FROM rides
)
SELECT driver_id, ride_id, fare_usd, started_at
FROM ranked
WHERE rk = 1
ORDER BY fare_usd DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q5. Drivers in the bottom decile of their city by acceptance rate
-- -----------------------------------------------------------------------------
WITH driver_city AS (
  SELECT
    r.driver_id,
    n.city_id,
    AVG(CASE WHEN req.accepted = 1 THEN 1.0 ELSE 0 END) AS accept_rate
  FROM requests req
  LEFT JOIN rides r ON req.request_id = r.request_id
  JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  WHERE r.driver_id IS NOT NULL
  GROUP BY r.driver_id, n.city_id
),
deciled AS (
  SELECT *,
         NTILE(10) OVER (PARTITION BY city_id ORDER BY accept_rate) AS decile
  FROM driver_city
)
SELECT city_id, driver_id, ROUND(accept_rate, 3) AS accept_rate, decile
FROM deciled
WHERE decile = 1
ORDER BY city_id, accept_rate
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Q6. Each driver's longest streak of consecutive days with >=1 ride
--     (gaps-and-islands trick)
-- -----------------------------------------------------------------------------
WITH driver_days AS (
  SELECT DISTINCT driver_id, date(started_at) AS d FROM rides
),
labeled AS (
  SELECT driver_id, d,
         julianday(d) - ROW_NUMBER() OVER (PARTITION BY driver_id ORDER BY d) AS grp
  FROM driver_days
),
streaks AS (
  SELECT driver_id, grp, COUNT(*) AS streak_len
  FROM labeled
  GROUP BY driver_id, grp
)
SELECT driver_id, MAX(streak_len) AS longest_streak
FROM streaks
GROUP BY driver_id
ORDER BY longest_streak DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q7. Ratio of each rider's last 7-day spend to their lifetime average
--     (window over a window)
-- -----------------------------------------------------------------------------
WITH rider_daily AS (
  SELECT req.rider_id,
         date(r.started_at) AS day,
         SUM(r.fare_usd) AS daily_spend
  FROM rides r
  JOIN requests req ON r.request_id = req.request_id
  GROUP BY req.rider_id, day
),
with_windows AS (
  SELECT
    rider_id,
    day,
    daily_spend,
    SUM(daily_spend) OVER (
      PARTITION BY rider_id
      ORDER BY day
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS last7d_spend,
    AVG(daily_spend) OVER (
      PARTITION BY rider_id
    ) AS lifetime_daily_avg
  FROM rider_daily
)
SELECT
  rider_id, day,
  ROUND(last7d_spend, 2)         AS last7d_spend,
  ROUND(lifetime_daily_avg, 2)   AS lifetime_avg,
  ROUND(last7d_spend / NULLIF(lifetime_daily_avg, 0), 2) AS ratio
FROM with_windows
ORDER BY rider_id, day
LIMIT 15;
