# Module 5: Window Functions

## What this module covers

Window functions are the single most powerful SQL feature for analytical
work. They let you compute things like "rank within group", "running
total", "previous row's value", and "moving average" without writing a
self-join.

If you only learn one advanced SQL topic, learn this one. **It's also
the topic that comes up most often in tech interviews.**

## The mental model

A window function:

- Computes an aggregate (or rank, or lag) **across a set of rows
  related to the current row** (the "window")
- Returns **one value per input row** (unlike GROUP BY, which collapses
  rows)
- Lives in the SELECT clause, not in a separate query

The window is defined by an `OVER (...)` clause:

```sql
SELECT
  driver_id,
  fare_usd,
  AVG(fare_usd) OVER (PARTITION BY driver_id) AS driver_avg_fare,
  fare_usd - AVG(fare_usd) OVER (PARTITION BY driver_id) AS deviation
FROM rides;
```

This returns *every* ride along with the driver's average fare and the
ride's deviation from that average. **No GROUP BY, no subquery.**

## The OVER clause

```sql
function() OVER (
  PARTITION BY col1, col2     -- groups (like GROUP BY)
  ORDER BY     col3 DESC      -- ordering within each partition
  ROWS BETWEEN ... AND ...    -- the window frame
)
```

Three parts:

1. **`PARTITION BY`** — splits the rows into groups. The function is
   computed independently within each partition.
2. **`ORDER BY`** — orders rows within each partition. Required for
   ranking and row-position functions; optional for plain aggregates.
3. **`ROWS BETWEEN`** — defines the window frame (which rows are
   actually in the window). Defaults vary by function.

## The four function families

### 1. Aggregates (with windowing)

`SUM`, `AVG`, `MIN`, `MAX`, `COUNT` — all of them work as window
functions. They compute an aggregate over the window relative to each
row.

```sql
SELECT driver_id, started_at, fare_usd,
       SUM(fare_usd) OVER (PARTITION BY driver_id ORDER BY started_at) AS running_total
FROM   rides;
```

The `ORDER BY` inside `OVER` makes this a *running* total — the sum
includes all rides up to and including the current row, in chronological
order.

### 2. Ranking

`ROW_NUMBER()`, `RANK()`, `DENSE_RANK()`, `NTILE(n)`.

| Function | Behavior on ties |
|---|---|
| `ROW_NUMBER()` | Arbitrary order, but always gives 1, 2, 3, ... |
| `RANK()` | Same rank for ties; gaps after (1, 2, 2, 4) |
| `DENSE_RANK()` | Same rank for ties; no gaps (1, 2, 2, 3) |
| `NTILE(n)` | Splits into n equal-sized buckets |

```sql
SELECT driver_id, fare_usd,
       RANK() OVER (PARTITION BY driver_id ORDER BY fare_usd DESC) AS fare_rank
FROM rides;
```

This ranks each driver's rides by fare. The top fare for each driver
gets rank 1.

### 3. Offset functions

`LAG(col, n, default)`, `LEAD(col, n, default)`.

```sql
SELECT driver_id, started_at, fare_usd,
       LAG(started_at, 1) OVER (PARTITION BY driver_id ORDER BY started_at) AS prev_ride
FROM rides;
```

For each ride, this returns the driver's *previous* ride start time.
For the first ride per driver, it returns NULL (or the default if you
provide one).

`LEAD` is the same but looks forward.

### 4. First/last

`FIRST_VALUE(col)`, `LAST_VALUE(col)`, `NTH_VALUE(col, n)`.

```sql
SELECT driver_id, fare_usd,
       FIRST_VALUE(fare_usd) OVER (PARTITION BY driver_id ORDER BY started_at) AS first_fare
FROM rides;
```

Be careful: `LAST_VALUE` defaults to a frame that *only includes the
current row*, so you usually need to explicitly extend the frame:

```sql
LAST_VALUE(fare_usd) OVER (
  PARTITION BY driver_id
  ORDER BY started_at
  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
) AS last_fare
```

This is the most common foot-gun in window functions.

## The frame clause

`ROWS BETWEEN start AND end` defines which rows are in the window. The
options:

- `UNBOUNDED PRECEDING` — start of partition
- `n PRECEDING` — n rows before current
- `CURRENT ROW`
- `n FOLLOWING` — n rows after current
- `UNBOUNDED FOLLOWING` — end of partition

Three commonly-needed frames:

```sql
-- Running total (default frame for aggregates with ORDER BY)
SUM(fare_usd) OVER (PARTITION BY driver_id ORDER BY started_at
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)

-- 7-day moving average (assuming daily granularity)
AVG(fare_usd) OVER (PARTITION BY driver_id ORDER BY started_at
                    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)

-- "Total over the whole partition"
SUM(fare_usd) OVER (PARTITION BY driver_id
                    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
```

The default frame **changes depending on whether you have ORDER BY**:

- Without `ORDER BY`: the entire partition
- With `ORDER BY` (and no explicit frame): `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`

This default-frame behavior is the source of subtle bugs. **When in
doubt, write the frame explicitly.**

## Pattern 1: Top-N per group

The cleanest version of "the highest-fare ride per driver":

```sql
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY driver_id ORDER BY fare_usd DESC) AS rk
  FROM rides
)
SELECT driver_id, ride_id, fare_usd
FROM   ranked
WHERE  rk = 1;
```

Use `ROW_NUMBER` if you want exactly one row per group (ties broken
arbitrarily). Use `RANK` or `DENSE_RANK` if you want all tied rows.

## Pattern 2: Time since previous event

```sql
SELECT
  ride_id, driver_id, started_at,
  LAG(started_at, 1) OVER (PARTITION BY driver_id ORDER BY started_at) AS prev,
  julianday(started_at) - julianday(
    LAG(started_at, 1) OVER (PARTITION BY driver_id ORDER BY started_at)
  ) AS days_since_last
FROM rides;
```

The pattern: compute `LAG` once, then do arithmetic on it. You can
also wrap the whole thing in a CTE to avoid repeating the OVER clause.

## Pattern 3: Rolling average

```sql
SELECT
  date(started_at) AS day,
  COUNT(*) AS rides_today,
  AVG(COUNT(*)) OVER (
    ORDER BY date(started_at)
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ) AS rolling_7d_avg
FROM rides
GROUP BY day;
```

Note: you can window over an aggregate. The inner `COUNT(*)` aggregates
within each day; the outer `AVG(...)` averages those daily counts over
the 7-day window.

## Pattern 4: Percentile / NTILE

"Drivers in the bottom 10% by acceptance rate, *within their city*":

```sql
WITH driver_city AS (
  SELECT
    r.driver_id,
    n.city_id,
    AVG(CASE WHEN req.accepted = 1 THEN 1.0 ELSE 0 END) AS accept_rate
  FROM   requests req
  LEFT JOIN rides r ON req.request_id = r.request_id
  JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
  WHERE  r.driver_id IS NOT NULL
  GROUP BY r.driver_id, n.city_id
)
SELECT *
FROM (
  SELECT *, NTILE(10) OVER (PARTITION BY city_id ORDER BY accept_rate) AS decile
  FROM driver_city
)
WHERE decile = 1;
```

Compare with the correlated-subquery version we wrote in Module 3 —
this is a one-liner.

## Pattern 5: Gaps and islands

"Each driver's longest streak of consecutive days with at least one
ride."

The classic gaps-and-islands trick:

```sql
WITH driver_days AS (
  SELECT DISTINCT driver_id, date(started_at) AS d FROM rides
),
labeled AS (
  SELECT
    driver_id, d,
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
```

The trick: subtracting the row number from the date gives a "constant"
for any consecutive run of days. Group by that constant and you get
each streak.

This is a classic "did you understand window functions" interview
question. The first time you see it it's mind-bending; after that it's
a tool in your kit.

## Common traps

### 1. Forgetting `ORDER BY` for ranking

`ROW_NUMBER() OVER (PARTITION BY x)` without an `ORDER BY` is
non-deterministic — the engine picks an arbitrary order. Always include
`ORDER BY`.

### 2. Wrong default frame for `LAST_VALUE`

`LAST_VALUE(col) OVER (ORDER BY ...)` defaults to a frame ending at
`CURRENT ROW`, so it returns the *current* row's value, not the partition's
last value. Fix:

```sql
LAST_VALUE(col) OVER (
  ORDER BY ...
  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

### 3. Window functions in WHERE / HAVING

You can't put a window function in `WHERE` (windows are computed after
`WHERE`). The fix: wrap the query in a CTE or subquery and filter in
the outer query.

```sql
-- WRONG
SELECT * FROM rides
WHERE ROW_NUMBER() OVER (PARTITION BY driver_id ORDER BY fare_usd) = 1;

-- RIGHT
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY driver_id ORDER BY fare_usd) AS rk
  FROM rides
)
SELECT * FROM ranked WHERE rk = 1;
```

### 4. Rolling window with gaps

`ROWS BETWEEN 6 PRECEDING` counts *rows*, not days. If your data has
gaps (no rides on some days), a "7-row" window isn't a "7-day" window.
Fix: pre-aggregate to one row per day, then use `ROWS BETWEEN 6
PRECEDING`. Or use `RANGE BETWEEN INTERVAL '6' DAY PRECEDING` in
Postgres.

## Interview questions

1. **Rank drivers within each city by total earnings.** (`RANK`)
2. **For each ride, compute the time since the driver's previous ride.** (`LAG`)
3. **7-day rolling average of completed rides per city.** (Aggregate window)
4. **Each driver's longest streak of consecutive days with ≥ 1 ride.** (Gaps and islands)
5. **Ratio of each rider's last 7-day spend to their lifetime average.** (Window of windows)
