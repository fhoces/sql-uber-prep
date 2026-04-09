# Module 3: GROUP BY, HAVING, and Aggregation Patterns

## What this module covers

GROUP BY is the workhorse of analytical SQL. Module 1 introduced the
basic syntax; this module covers the *patterns* that come up over and
over: cohort analysis, conversion funnels, per-group rankings, and
"compare to the global average."

If you can write these from memory you're past the bar for any data
job interview.

## Quick refresher

```sql
SELECT  group_col, agg_func(other_col) AS metric
FROM    table_name
WHERE   row_filter
GROUP BY group_col
HAVING  group_filter
ORDER BY metric DESC;
```

The execution order matters: WHERE filters before grouping; HAVING
filters after.

## Pattern 1: City-level dashboard

The classic "one row per city, with all the metrics."

```sql
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
```

This is what a "dashboard query" looks like in real life. It's just
GROUP BY + a bunch of aggregates.

## Pattern 2: Compare to the global average

"Cities where the average wait time is above the global average."

Two ways to do this. The subquery way:

```sql
SELECT c.name, AVG(r.fare_usd) AS avg_fare
FROM rides r
JOIN requests req ON r.request_id = req.request_id
JOIN neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN cities c ON n.city_id = c.city_id
GROUP BY c.name
HAVING AVG(r.fare_usd) > (SELECT AVG(fare_usd) FROM rides);
```

The subquery computes the global average, and `HAVING` filters groups
above it. The window-function way (Module 5) is shorter, but this works
in any SQL dialect.

## Pattern 3: Conversion funnel

"For each step in a process, how many users made it that far?"

For ride-sharing, the funnel is `request → accept → ride → 5-star`.

```sql
SELECT
  COUNT(*)                                              AS step1_requests,
  SUM(CASE WHEN req.accepted = 1 THEN 1 ELSE 0 END)     AS step2_accepted,
  SUM(CASE WHEN r.ride_id IS NOT NULL THEN 1 ELSE 0 END) AS step3_completed,
  SUM(CASE WHEN r.rider_rating = 5 THEN 1 ELSE 0 END)   AS step4_5star,

  ROUND(1.0 * SUM(CASE WHEN req.accepted = 1 THEN 1 ELSE 0 END) / COUNT(*), 3)
                                                        AS conv_request_to_accept,
  ROUND(1.0 * SUM(CASE WHEN r.rider_rating = 5 THEN 1 ELSE 0 END) /
        SUM(CASE WHEN r.ride_id IS NOT NULL THEN 1 ELSE 0 END), 3)
                                                        AS conv_completed_to_5star
FROM   requests req
LEFT JOIN rides r ON req.request_id = r.request_id;
```

The pattern: `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` to count
qualifying rows at each step, then divide to get conversion rates.

## Pattern 4: Per-group ranking (without window functions)

"For each city, the neighborhood with the most rides."

Without window functions (Module 5), you do it with a self-join or
correlated subquery:

```sql
WITH city_nbhd_rides AS (
  SELECT c.name AS city, n.name AS nbhd, COUNT(*) AS n_rides
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  JOIN   cities c ON n.city_id = c.city_id
  GROUP BY c.name, n.name
)
SELECT city, nbhd, n_rides
FROM   city_nbhd_rides cnr
WHERE  n_rides = (
  SELECT MAX(n_rides)
  FROM   city_nbhd_rides cnr2
  WHERE  cnr2.city = cnr.city
);
```

This is ugly. With window functions you'd write:

```sql
WITH city_nbhd_rides AS (...)
SELECT city, nbhd, n_rides
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY n_rides DESC) AS rk
  FROM city_nbhd_rides
)
WHERE rk = 1;
```

We do this properly in Module 5. For now, learn the correlated-subquery
pattern because it's a fallback for any dialect that lacks window
functions.

## Pattern 5: Cohort retention table

"For each signup-month cohort, how many users were active in each
subsequent month?"

```sql
WITH cohort AS (
  SELECT rider_id,
         strftime('%Y-%m', signup_date) AS cohort_month
  FROM   riders
),
activity AS (
  SELECT rider_id,
         strftime('%Y-%m', requested_at) AS activity_month
  FROM   requests
  GROUP BY rider_id, activity_month
)
SELECT
  c.cohort_month,
  a.activity_month,
  COUNT(DISTINCT c.rider_id) AS active_riders
FROM   cohort c
JOIN   activity a ON c.rider_id = a.rider_id
GROUP BY c.cohort_month, a.activity_month
ORDER BY c.cohort_month, a.activity_month;
```

The pattern: build the cohort table (one row per user with their
cohort), build the activity table (user-month pairs), join them, and
count distinct users per (cohort, activity) pair.

This is the canonical "retention curve" query. Variations: relative
months since signup, conditional on having been active in the previous
month, etc.

## Pattern 6: Bottom-N within a group

"Drivers in the bottom 10% of their city by acceptance rate."

```sql
WITH driver_accept AS (
  SELECT
    r.driver_id,
    n.city_id,
    AVG(CASE WHEN r.ride_id IS NOT NULL THEN 1.0 ELSE 0 END) AS accept_rate
  FROM   requests req
  LEFT JOIN rides r ON req.request_id = r.request_id
  JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  WHERE  req.accepted_by_driver_id IS NOT NULL
  GROUP BY r.driver_id, n.city_id
)
SELECT
  driver_id,
  city_id,
  accept_rate
FROM   driver_accept da
WHERE  accept_rate <= (
  SELECT MIN(accept_rate)
  FROM (
    SELECT accept_rate
    FROM   driver_accept
    WHERE  city_id = da.city_id
    ORDER BY accept_rate
    LIMIT  CAST(0.10 *
      (SELECT COUNT(*) FROM driver_accept WHERE city_id = da.city_id) AS INTEGER)
  )
);
```

This is genuinely hard to write without window functions. With
`NTILE(10) OVER (PARTITION BY city_id ORDER BY accept_rate)` it
becomes a one-liner. We cover that in Module 5.

## Common traps

### 1. Selecting non-aggregated columns without grouping

```sql
SELECT city, name, COUNT(*) FROM cities GROUP BY city;
```

In strict SQL this is an error: `name` isn't in the GROUP BY and isn't
aggregated, so the engine doesn't know which `name` to return per
group. SQLite is lenient and picks an arbitrary one, which is worse —
you get a result that looks fine but is wrong.

**Rule:** every column in `SELECT` must either appear in `GROUP BY` or
be inside an aggregate function.

### 2. `COUNT` vs `COUNT(DISTINCT ...)`

`COUNT(*)` counts rows. `COUNT(driver_id)` counts non-NULL driver IDs
(usually the same as `COUNT(*)` if the column has no nulls).
`COUNT(DISTINCT driver_id)` counts unique driver IDs. People mix these
up constantly. Be deliberate.

### 3. Counting "users" after a join

If you join `requests` to `rides`, each accepted request becomes one
row. Then `COUNT(DISTINCT rider_id)` is fine, but `COUNT(rider_id)`
counts *rides*, not riders. The fix: `COUNT(DISTINCT)` or count before
the join.

### 4. Filtering aggregates with WHERE

`WHERE COUNT(*) > 10` is a syntax error. Aggregates don't exist in
`WHERE`. Use `HAVING` for that.

## Interview questions

1. **City-by-city ride volume + average fare + driver count, sorted by volume.**
2. **Cities where average wait time exceeds the global average.**
3. **Conversion rate (request → completed ride) by hour of day.**
4. **Drivers with acceptance rate in the bottom 10% of their city.**
5. **Cohort retention table: signup-month × activity-month → active riders.**
