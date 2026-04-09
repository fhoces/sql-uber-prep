-- =============================================================================
-- Module 3: GROUP BY, HAVING, Conversion Funnels
-- =============================================================================

.headers on
.mode column

-- -----------------------------------------------------------------------------
-- Q1. City-by-city dashboard
-- -----------------------------------------------------------------------------
SELECT
  c.name                            AS city,
  COUNT(DISTINCT r.driver_id)       AS active_drivers,
  COUNT(*)                          AS n_rides,
  ROUND(AVG(r.fare_usd), 2)         AS avg_fare,
  ROUND(SUM(r.fare_usd), 0)         AS total_revenue
FROM rides r
JOIN requests req ON r.request_id = req.request_id
JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN cities c ON n.city_id = c.city_id
GROUP BY c.name
ORDER BY total_revenue DESC;


-- -----------------------------------------------------------------------------
-- Q2. Cities where the average fare exceeds the global average
-- -----------------------------------------------------------------------------
SELECT c.name AS city,
       ROUND(AVG(r.fare_usd), 2) AS avg_fare,
       (SELECT ROUND(AVG(fare_usd), 2) FROM rides) AS global_avg
FROM rides r
JOIN requests req ON r.request_id = req.request_id
JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN cities c ON n.city_id = c.city_id
GROUP BY c.name
HAVING AVG(r.fare_usd) > (SELECT AVG(fare_usd) FROM rides)
ORDER BY avg_fare DESC;


-- -----------------------------------------------------------------------------
-- Q3. Hourly conversion rate (request -> completed ride)
-- -----------------------------------------------------------------------------
SELECT
  strftime('%H', requested_at) AS hour,
  COUNT(*)                     AS n_requests,
  SUM(accepted)                AS n_accepted,
  ROUND(1.0 * SUM(accepted) / COUNT(*), 3) AS accept_rate
FROM requests
GROUP BY hour
ORDER BY hour;


-- -----------------------------------------------------------------------------
-- Q4. Conversion funnel: request -> accept -> 5-star
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                                AS step1_requests,
  SUM(CASE WHEN req.accepted = 1 THEN 1 ELSE 0 END)       AS step2_accepted,
  SUM(CASE WHEN r.ride_id IS NOT NULL THEN 1 ELSE 0 END)  AS step3_completed,
  SUM(CASE WHEN r.rider_rating = 5 THEN 1 ELSE 0 END)     AS step4_5star,
  ROUND(1.0 * SUM(CASE WHEN r.rider_rating = 5 THEN 1 ELSE 0 END) /
        COUNT(*), 3)                                      AS overall_conv
FROM   requests req
LEFT JOIN rides r ON req.request_id = r.request_id;


-- -----------------------------------------------------------------------------
-- Q5. Cohort retention table (signup-month x activity-month)
-- -----------------------------------------------------------------------------
WITH cohort AS (
  SELECT rider_id, strftime('%Y-%m', signup_date) AS cohort_month
  FROM   riders
),
activity AS (
  SELECT DISTINCT
         rider_id,
         strftime('%Y-%m', requested_at) AS activity_month
  FROM   requests
)
SELECT
  c.cohort_month,
  a.activity_month,
  COUNT(DISTINCT c.rider_id) AS active_riders
FROM   cohort c
JOIN   activity a ON c.rider_id = a.rider_id
GROUP BY c.cohort_month, a.activity_month
ORDER BY c.cohort_month, a.activity_month
LIMIT 30;


-- -----------------------------------------------------------------------------
-- Q6. Drivers with above-average rating per city
-- -----------------------------------------------------------------------------
WITH driver_city_ratings AS (
  SELECT r.driver_id,
         n.city_id,
         AVG(r.rider_rating) AS avg_rating
  FROM rides r
  JOIN requests req ON r.request_id = req.request_id
  JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  WHERE r.rider_rating IS NOT NULL
  GROUP BY r.driver_id, n.city_id
)
SELECT dcr.driver_id, dcr.city_id, ROUND(dcr.avg_rating, 2) AS avg_rating
FROM   driver_city_ratings dcr
WHERE  dcr.avg_rating > (
  SELECT AVG(avg_rating)
  FROM   driver_city_ratings dcr2
  WHERE  dcr2.city_id = dcr.city_id
)
ORDER BY dcr.city_id, dcr.avg_rating DESC
LIMIT 20;
