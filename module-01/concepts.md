# Module 1: SELECT, WHERE, Aggregates

## What this module covers

The basics: pulling data out of a single table, filtering rows, sorting,
and computing simple aggregates. This is ~80% of what you'll do in any
analytical job, and it's the first thing the interviewer will check.

By the end of this module you should be able to write any of these
queries from a cold start in under two minutes each.

## The schema

Every exercise in this course runs against a SQLite database at
`data/uber.sqlite`. Build it once with `Rscript data/setup.R`. The
schema:

```
cities         (city_id, name, country, lead_pm)
neighborhoods  (nbhd_id, city_id, name, pct_minority, median_income)
drivers        (driver_id, signup_date, gender, home_nbhd_id)
riders         (rider_id, signup_date, home_nbhd_id)
requests       (request_id, rider_id, pickup_nbhd_id, dropoff_nbhd_id,
                requested_at, accepted, accepted_by_driver_id)
rides          (ride_id, request_id, driver_id, started_at, ended_at,
                distance_mi, fare_usd, surge_mult, rider_rating)
```

In this module we work mostly with the `rides`, `drivers`, and
`requests` tables.

## The core syntax you need

```sql
SELECT col1, col2, agg_func(col3) AS result_name
FROM   table_name
WHERE  some_condition
GROUP BY col1, col2
HAVING aggregate_condition
ORDER BY col1 DESC
LIMIT 10;
```

The execution order is **not** the written order. Logically the engine
processes:

1. `FROM`
2. `WHERE`
3. `GROUP BY`
4. `HAVING`
5. `SELECT`
6. `ORDER BY`
7. `LIMIT`

This matters when you're trying to use a column alias in `WHERE`
(doesn't work — `SELECT` happens later) but it does work in `ORDER BY`
(after `SELECT`).

## The five things to remember

1. **`COUNT(*)` vs `COUNT(col)`** — `COUNT(*)` counts rows;
   `COUNT(col)` counts non-NULL values in `col`. They differ when there
   are NULLs.
2. **`COUNT(DISTINCT col)`** — counts distinct non-NULL values. This is
   the most common aggregate you'll write that isn't `COUNT(*)`.
3. **`AVG` ignores NULLs.** So does `SUM`. You usually want this. If you
   want to count NULLs as zeros, use `COALESCE(col, 0)` first.
4. **`WHERE` filters rows; `HAVING` filters groups.** `WHERE` happens
   before grouping; `HAVING` happens after. You can't put an aggregate
   in `WHERE`.
5. **`LIMIT` does not give you a sample.** It gives you the first N rows
   *after* `ORDER BY`. If you don't sort, the order is undefined and
   `LIMIT 10` may give you anything.

## Date and time handling in SQLite

SQLite stores dates as TEXT in ISO format (`YYYY-MM-DD HH:MM:SS`). The
useful functions:

```sql
date(col)                          -- '2025-01-15'
strftime('%Y-%m', col)             -- '2025-01' (year-month)
strftime('%w', col)                -- day of week, 0 = Sunday
strftime('%H', col)                -- hour of day
date(col, 'start of month')        -- first of the month
date(col, '-7 days')               -- a week ago
julianday(b) - julianday(a)        -- difference in days
```

In Postgres or MySQL you'd use different functions (`DATE_TRUNC`,
`EXTRACT(...)`). The patterns are the same; the syntax is slightly
different.

## Common patterns to memorize

### Top-N

```sql
SELECT *
FROM rides
ORDER BY fare_usd DESC
LIMIT 10;
```

### Filtered aggregate

```sql
SELECT COUNT(*) AS rides_last_week
FROM rides
WHERE date(started_at) >= date('2025-12-25');
```

### Group-by aggregate

```sql
SELECT pickup_nbhd_id, COUNT(*) AS n_rides, AVG(fare_usd) AS avg_fare
FROM rides
JOIN requests USING (request_id)
GROUP BY pickup_nbhd_id
ORDER BY n_rides DESC;
```

### Having (filter on the aggregate)

```sql
SELECT driver_id, COUNT(*) AS n_rides
FROM rides
GROUP BY driver_id
HAVING COUNT(*) >= 100
ORDER BY n_rides DESC;
```

### Conditional count

```sql
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN accepted = 1 THEN 1 ELSE 0 END) AS accepted_count,
  AVG(CASE WHEN accepted = 1 THEN 1.0 ELSE 0 END) AS accept_rate
FROM requests;
```

The `CASE WHEN ... THEN 1 ELSE 0 END` trick is the SQL equivalent of
`mean(x == "foo")` in R. Memorize it.

## Interview questions in this module

1. **Total rides per city last week.** Hint: you'll need to join `rides`,
   `requests`, `neighborhoods`, and `cities` (we'll cover joins
   properly in Module 2 — for now, just write the per-`pickup_nbhd_id`
   version and we'll fix it later).

2. **Average fare by hour of day.**
   ```sql
   SELECT strftime('%H', started_at) AS hour, AVG(fare_usd) AS avg_fare
   FROM rides
   GROUP BY hour
   ORDER BY hour;
   ```

3. **Drivers who completed at least 100 rides in 2025.**
   ```sql
   SELECT driver_id, COUNT(*) AS n
   FROM rides
   WHERE date(started_at) BETWEEN '2025-01-01' AND '2025-12-31'
   GROUP BY driver_id
   HAVING COUNT(*) >= 100
   ORDER BY n DESC;
   ```

4. **Top-10 longest trips with their driver and fare.**
   ```sql
   SELECT ride_id, driver_id, distance_mi, fare_usd
   FROM rides
   ORDER BY distance_mi DESC
   LIMIT 10;
   ```

5. **Conversion rate of requests to rides, by month.**
   ```sql
   SELECT
     strftime('%Y-%m', requested_at) AS month,
     COUNT(*)                          AS n_requests,
     SUM(accepted)                     AS n_accepted,
     1.0 * SUM(accepted) / COUNT(*)    AS accept_rate
   FROM requests
   GROUP BY month
   ORDER BY month;
   ```

(Note the `1.0 *` — without it, SQLite does integer division and you get
zeros.)

## What can trip you up

- **Integer division.** `SUM(x) / COUNT(*)` returns 0 if both are
  integers and the result is < 1. Always cast: `1.0 * SUM(x) / COUNT(*)`
  or `CAST(SUM(x) AS FLOAT) / COUNT(*)`.
- **NULLs in aggregates.** `AVG` and `SUM` skip NULLs; `COUNT(*)`
  doesn't. If 100 rows have `fare_usd = NULL`, `AVG(fare_usd)` is the
  average of the non-NULL ones, not divided by 100.
- **Aliases in WHERE.** `SELECT fare * 1.5 AS surge_fare FROM rides
  WHERE surge_fare > 50` doesn't work. Repeat the expression in the
  `WHERE` clause, or use a subquery.
- **String comparison.** SQLite is case-sensitive by default. Use
  `LOWER()` or the `COLLATE NOCASE` hint if you need case-insensitive.
- **`BETWEEN` is inclusive on both ends.** `WHERE x BETWEEN 1 AND 10`
  is `x >= 1 AND x <= 10`.

## Going further

Module 2 introduces JOINs, which is where SQL really starts paying off.
Module 3 expands GROUP BY into the patterns you need for cohort
analysis, conversion funnels, and disaggregated metrics. Modules 4 and
5 cover the more advanced stuff.
