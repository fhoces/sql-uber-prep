# Intro to SQL

A 5-module SQL refresher built around interview-style questions for a
ride-sharing analytical role. Every module is concept → code → 3–6
interview questions you should be able to write from a cold start.

> **Live slides:** *(set up after enabling GitHub Pages on this repo)*

## Why this exists

Most SQL tutorials are general-purpose and slow. This one is targeted:
the goal is to walk into a 30-minute SQL portion of a tech-economics
interview and be able to write any of the canonical analytical queries
without thinking about syntax.

The questions are ride-sharing themed because that's the most common
domain for the interview slot it's preparing you for, but the patterns
generalize to any platform with a similar relational schema.

## How to use this repo

```bash
# 1. Build the synthetic SQLite database (once)
Rscript data/setup.R

# 2. Read the concepts file for each module
open module-01/concepts.md

# 3. Walk through the slide deck
open module-01/slides.html

# 4. Drill the queries
sqlite3 data/uber.sqlite < module-01/exercise.sql

# 5. Re-write each query from memory until you can do it in 2 minutes
```

The schema:

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

## Modules

| # | Module | Topics | Sample interview questions |
|---|--------|--------|---|
| **1** | [SELECT, WHERE, Aggregates](module-01/) | Filter, sort, aggregate, CASE WHEN, dates | Top-10 longest trips, hourly avg fare, monthly conversion rate |
| **2** | [JOINs](module-02/) | INNER, LEFT, anti-join, multi-table chains | Unique drivers per rider, driver tenure attached to each ride |
| **3** | [GROUP BY, HAVING, Conversion Funnels](module-03/) | Per-group metrics, compare-to-global, funnels, cohort retention | City dashboards, funnel analysis, cohort tables |
| **4** | [Subqueries and CTEs](module-04/) | Scalar / table / correlated subqueries, multi-step CTEs | Each rider's first ride, multi-step funnel as CTE chain |
| **5** | [Window Functions](module-05/) | OVER, PARTITION BY, ranking, LAG/LEAD, gaps and islands | Top-N per group, rolling avg, longest streak |

## Dependencies

To build the database and render slides locally:

```r
install.packages(c("DBI", "RSQLite", "tidyverse", "rmarkdown", "xaringan"))
```

The exercise files are pure SQL and only need the `sqlite3` CLI.

## Companion courses

This is part of a small set of refreshers for the same applied
policy-economist interview prep:

- [discrimination-econ-refresher](https://github.com/fhoces/discrimination-econ-refresher) — labor-econ literature on discrimination
- [ml-discrimination-refresher](https://github.com/fhoces/ml-discrimination-refresher) — ML fundamentals + algorithmic fairness
- [python-for-r-users](https://github.com/fhoces/python-for-r-users) — pandas + statsmodels for someone coming from R
