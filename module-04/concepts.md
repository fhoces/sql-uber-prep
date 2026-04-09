# Module 4: Subqueries and CTEs

## What this module covers

Once your queries get more than ~5 lines you need a way to organize
intermediate results. SQL gives you two tools:

- **Subqueries** — a query inside another query
- **Common Table Expressions (CTEs)** — named subqueries that read
  top-to-bottom

CTEs are nicer to read; subqueries are sometimes shorter. Both compile
to roughly the same execution plan in modern engines, so pick whichever
is more readable.

By the end of this module you should be able to write a 30-line
multi-step query as a chain of CTEs and have it work the first time.

## Subquery flavors

### Scalar subquery

Returns a single value. You can use it anywhere a value would go.

```sql
SELECT *
FROM   rides
WHERE  fare_usd > (SELECT AVG(fare_usd) FROM rides);
```

The inner query returns one number; the outer query uses it like a
constant.

### Table subquery

Returns a table. You use it in a `FROM` or `JOIN`. The outer query
treats it like any other table.

```sql
SELECT t.driver_id, t.n_rides
FROM (
  SELECT driver_id, COUNT(*) AS n_rides
  FROM rides
  GROUP BY driver_id
) t
WHERE t.n_rides > 100;
```

You can do this in one query with `HAVING`, but the subquery form
generalizes to more complex cases.

### Correlated subquery

A subquery that references a column from the outer query. It runs once
per outer row.

```sql
SELECT d.driver_id,
       (SELECT COUNT(*) FROM rides r WHERE r.driver_id = d.driver_id) AS n_rides
FROM   drivers d;
```

Convenient but slow on large tables — the inner query runs once per
driver. Modern optimizers sometimes rewrite these as joins, but don't
count on it.

## CTEs

A CTE is a named subquery introduced with `WITH`:

```sql
WITH driver_rides AS (
  SELECT driver_id, COUNT(*) AS n_rides
  FROM   rides
  GROUP BY driver_id
)
SELECT * FROM driver_rides WHERE n_rides > 100;
```

Multiple CTEs:

```sql
WITH
  driver_rides AS (
    SELECT driver_id, COUNT(*) AS n_rides FROM rides GROUP BY driver_id
  ),
  rider_rides AS (
    SELECT rider_id, COUNT(*) AS n_requests FROM requests GROUP BY rider_id
  )
SELECT *
FROM   driver_rides
JOIN   rider_rides ON ... ;
```

The pattern: each CTE is one logical step. You read top-to-bottom, just
like a script. This is the right way to write any non-trivial query.

## Pattern 1: Multi-step funnel

The conversion-funnel query from Module 3 was already inside a single
SELECT. With more steps and per-step disaggregation, you want CTEs:

```sql
WITH step1 AS (
  SELECT request_id, rider_id, requested_at, accepted
  FROM   requests
  WHERE  date(requested_at) BETWEEN '2025-12-01' AND '2025-12-31'
),
step2 AS (
  SELECT s.request_id, s.rider_id, r.ride_id, r.fare_usd, r.rider_rating
  FROM   step1 s
  LEFT JOIN rides r ON s.request_id = r.request_id
),
step3 AS (
  SELECT
    COUNT(*) AS n_requests,
    SUM(CASE WHEN ride_id IS NOT NULL THEN 1 ELSE 0 END) AS n_completed,
    SUM(CASE WHEN rider_rating = 5 THEN 1 ELSE 0 END)    AS n_5star
  FROM step2
)
SELECT * FROM step3;
```

The CTEs are *named intermediate results*. You can comment each one,
test each one in isolation, and the engine will fold them all into a
single query at execution time.

## Pattern 2: Cohort retention with CTEs

We did this in Module 3. Here it is rewritten cleanly:

```sql
WITH cohort AS (
  SELECT rider_id, strftime('%Y-%m', signup_date) AS cohort_month
  FROM   riders
),
activity AS (
  SELECT DISTINCT
         rider_id,
         strftime('%Y-%m', requested_at) AS activity_month
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
ORDER BY cohort_month, activity_month;
```

## Pattern 3: First / last / only

"Each rider's first ride and the city it was in":

```sql
WITH first_ride AS (
  SELECT req.rider_id,
         MIN(r.started_at) AS first_started_at
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  GROUP BY req.rider_id
)
SELECT
  fr.rider_id,
  fr.first_started_at,
  c.name AS first_city
FROM   first_ride fr
JOIN   rides r ON r.started_at = fr.first_started_at
JOIN   requests req ON r.request_id = req.request_id
JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN   cities c ON n.city_id = c.city_id
LIMIT 10;
```

The pattern: a CTE finds the "first" row (by date / fare / whatever),
then a join attaches the rest of that row's information.

This is a *very* common interview question. The window-function
solution (Module 5) is cleaner — `ROW_NUMBER() OVER (PARTITION BY
rider_id ORDER BY started_at) = 1` — but the CTE pattern works
everywhere.

## Pattern 4: Active in each of the last N periods

"Riders who took at least one ride in *each* of the last 4 weeks":

```sql
WITH last4 AS (
  SELECT '2025-12-08' AS week_start UNION ALL
  SELECT '2025-12-15' UNION ALL
  SELECT '2025-12-22' UNION ALL
  SELECT '2025-12-29'
),
active AS (
  SELECT DISTINCT
    req.rider_id,
    date(req.requested_at, '-' || strftime('%w', req.requested_at) || ' days')
      AS week_start
  FROM   requests req
  WHERE  date(req.requested_at) BETWEEN '2025-12-08' AND '2026-01-04'
)
SELECT rider_id
FROM   active
GROUP BY rider_id
HAVING COUNT(DISTINCT week_start) = 4;
```

The trick: collapse each request to its week, then `HAVING COUNT(DISTINCT
week_start) = N`.

## CTE vs subquery: when to use which

| Situation | Use |
|---|---|
| You reference the same intermediate twice | **CTE** (otherwise you'd duplicate the subquery) |
| You have ≥ 3 logical steps | **CTE** (readable) |
| You need a single value in a WHERE clause | **Scalar subquery** |
| The intermediate is a one-liner | **Subquery** |
| You need recursion (rare) | **Recursive CTE** (`WITH RECURSIVE`) |

The honest answer: in modern SQL you should default to CTEs. They're
more readable, easier to debug, and the optimizer handles them as well
as subqueries in 95% of cases.

## Recursive CTEs (the brief version)

A recursive CTE references itself. Useful for hierarchies (org charts,
geographic containment, threaded comments) and for generating sequences.

```sql
WITH RECURSIVE numbers(n) AS (
  SELECT 1
  UNION ALL
  SELECT n + 1 FROM numbers WHERE n < 10
)
SELECT * FROM numbers;
```

You probably won't need this for an Uber policy economist interview,
but it's good to know it exists.

## Common traps

### 1. Forgetting to JOIN to the original after a CTE

The first/last pattern often goes wrong because people forget the
second join. The CTE has `(rider_id, first_started_at)`, but you also
want the city — that requires re-joining to `rides → requests →
neighborhoods → cities` to find the row that matches.

### 2. CTEs that aren't materialized

In Postgres before v12, CTEs were always materialized (each one runs
once and the result is held in memory). After v12 they're inlined like
subqueries. SQLite inlines them. The result: don't expect a CTE to act
as a "memoization" layer unless you check your engine's behavior.

### 3. Naming collisions

A CTE name shadows a real table of the same name. Be careful when you
write `WITH rides AS (...)` — every reference to `rides` after that
points to your CTE.

## Interview questions

1. **For each rider, find the date of their first ride and the city it
   was in.**
2. **Month-over-month rider retention by signup cohort** (multi-CTE).
3. **Riders active in each of the last 4 weeks.**
4. **A 3-step funnel using 3 CTEs:** request → match → completed → 5-star.
5. **For each driver, the date and amount of their highest-fare ride.**
