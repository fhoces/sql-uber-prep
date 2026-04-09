# Module 2: JOINs

## What this module covers

The single most important SQL skill after `SELECT`. JOINs let you combine
rows from multiple tables. ~95% of analytical queries you'll write at any
data job involve at least one JOIN.

## The four flavors

| JOIN type | What it returns |
|---|---|
| `INNER JOIN` (or just `JOIN`) | Only rows where the join condition matches in both tables |
| `LEFT JOIN` | All rows from the left table; matched rows from the right (NULL if no match) |
| `RIGHT JOIN` | All rows from the right table; matched rows from the left (rarely used — flip and use LEFT) |
| `FULL OUTER JOIN` | All rows from both tables; NULLs where no match (SQLite supports this from 3.39+) |

The fifth pattern people forget: **anti-join** — "rows in A that have no
match in B". There's no `ANTI JOIN` keyword; you do it with
`LEFT JOIN ... WHERE B.id IS NULL`.

## Syntax

```sql
SELECT  a.col1, b.col2
FROM    table_a AS a
JOIN    table_b AS b
  ON    a.foreign_key = b.primary_key
WHERE   ...;
```

Three things to know:

1. **Always use table aliases** (`a`, `b`, etc.). It makes the query
   shorter and disambiguates columns with the same name in two tables.
2. **The `ON` clause is the join condition.** Anything that evaluates to
   TRUE/FALSE works, including non-equality joins.
3. **`USING (col)` is shorthand** for `ON a.col = b.col` when the column
   has the same name in both tables.

## Pattern: Inner JOIN

```sql
SELECT r.ride_id, d.gender, r.fare_usd
FROM   rides r
JOIN   drivers d ON r.driver_id = d.driver_id;
```

This returns one row per ride, with the driver's gender attached.
Equivalent in dplyr:

```r
rides |> inner_join(drivers, by = "driver_id")
```

## Pattern: LEFT JOIN

```sql
SELECT req.request_id, req.accepted, r.fare_usd
FROM   requests req
LEFT JOIN rides r ON req.request_id = r.request_id;
```

Returns all requests, with the ride info attached if the request was
accepted, or NULL otherwise. Use this when you want to keep "the
unmatched things on the left" in the output.

## Pattern: Anti-join

"Find drivers who have never had a ride from a specific neighborhood":

```sql
SELECT d.driver_id
FROM   drivers d
LEFT JOIN (
  SELECT DISTINCT r.driver_id
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  WHERE  req.pickup_nbhd_id = 5
) target ON d.driver_id = target.driver_id
WHERE  target.driver_id IS NULL;
```

The trick: LEFT JOIN to the subquery, then filter for `IS NULL` to keep
only the driver IDs that *didn't* match. This is the SQL idiom for "set
difference."

Equivalently with `NOT EXISTS`:

```sql
SELECT driver_id
FROM   drivers d
WHERE NOT EXISTS (
  SELECT 1
  FROM   rides r
  JOIN   requests req ON r.request_id = req.request_id
  WHERE  r.driver_id = d.driver_id
    AND  req.pickup_nbhd_id = 5
);
```

Some people find `NOT EXISTS` more readable; query optimizers usually
treat them the same.

## Pattern: Self-join

When a table needs to be joined against itself. Most common use:
"compare each row to a related row in the same table."

Example: for each ride, find the driver's *previous* ride. (Use a
window function in Module 5; for now, do it with a self-join.)

```sql
SELECT r1.ride_id, r1.driver_id, r1.started_at,
       MAX(r2.started_at) AS previous_ride
FROM   rides r1
LEFT JOIN rides r2
  ON   r1.driver_id = r2.driver_id
  AND  r2.started_at < r1.started_at
GROUP BY r1.ride_id;
```

## Pattern: Multi-table chain

Joining 3+ tables in sequence:

```sql
SELECT c.name AS city, n.name AS neighborhood, COUNT(*) AS n_rides
FROM   rides ri
JOIN   requests req ON ri.request_id = req.request_id
JOIN   neighborhoods n ON req.pickup_nbhd_id = n.nbhd_id
JOIN   cities c ON n.city_id = c.city_id
GROUP BY c.name, n.name
ORDER BY c.name, n_rides DESC;
```

The chain pattern: `rides → requests → neighborhoods → cities`. Each
join attaches one new piece of information. Build these step by step;
don't try to write a 5-table join from scratch.

## Common traps

### 1. Cartesian explosion

If you forget the `ON` clause, or use a non-restrictive condition, you
get the **Cartesian product** of the two tables — every row in A paired
with every row in B. With 39,000 rides and 800 drivers, that's 31.2
million rows. Always make sure your join condition is right before
hitting RUN.

### 2. Inner join silently dropping rows

`JOIN` only keeps rows that match. If 5% of your rides have a driver_id
that doesn't exist in `drivers` (data quality issue), an inner join
will silently drop them. The honest pattern: `LEFT JOIN` and check for
NULLs explicitly.

### 3. Aggregating after a join

When you JOIN before GROUP BY, you can accidentally **double-count** if
the join produces multiple rows per source row. Always check: "is this
join one-to-one, one-to-many, or many-to-many?"

For one-to-many (e.g., one driver, many rides), the aggregate is fine if
you GROUP BY the "one" side.

For many-to-many, you usually need to be careful — sum-then-join is
different from join-then-sum.

### 4. Filtering on the right table of a LEFT JOIN

```sql
SELECT req.*, r.fare_usd
FROM requests req
LEFT JOIN rides r ON req.request_id = r.request_id
WHERE r.fare_usd > 20;
```

This **silently turns the LEFT JOIN into an INNER JOIN** because the
WHERE filters out the NULL rows. If you want to preserve the LEFT JOIN
semantics, put the filter in the ON clause:

```sql
LEFT JOIN rides r
  ON req.request_id = r.request_id AND r.fare_usd > 20
```

This is one of the most common bugs in real SQL code. Watch for it in
code review.

## Interview questions in this module

1. **For each rider, how many *unique* drivers have they ridden with?**
2. **List drivers who have never accepted a request from a high-minority
   neighborhood (`pct_minority >= 0.5`).**
3. **Attach each ride to the driver's tenure in days at the time of the
   ride.**
4. **Find rider–driver pairs with at least 3 five-star ratings together.**
5. **City-by-city ride count plus the lead PM for each city.**

The exercise file works through all of these.
