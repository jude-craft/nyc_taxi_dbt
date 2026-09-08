# 🚕 NYC Taxi Analytics — dbt + DuckDB

> A modern, local-first analytics engineering project that transforms raw NYC Taxi & Limousine Commission (TLC) trip records into a clean, analytics-ready data model using **dbt-core** and **DuckDB**.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Data Sources](#2-data-sources)
3. [Tech Stack](#3-tech-stack)
4. [Project Architecture](#4-project-architecture)
5. [Folder Structure](#5-folder-structure)
6. [Data Model](#6-data-model)
7. [Seeds & Reference Data](#7-seeds--reference-data)
8. [Custom Macros](#8-custom-macros)
9. [Tests & Data Quality](#9-tests--data-quality)
10. [Getting Started](#10-getting-started)
11. [dbt Commands Reference](#11-dbt-commands-reference)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Project Overview

I built this project as a hands-on, end-to-end analytics engineering pipeline using the NYC TLC dataset — one of the largest publicly available transportation datasets in the world. The goal is to demonstrate how I apply the **dbt analytics engineering workflow** (source → staging → intermediate → marts) to clean, transform, enrich, and model raw taxi trip records into a production-quality star schema.

The pipeline covers:

- **Data ingestion** via a Python script that downloads and converts raw CSV files to Parquet and loads them into a local DuckDB database
- **Staging** that standardises column names, casts data types, and removes bad records
- **Intermediate** models that union Green and Yellow taxi data, enrich trips with payment descriptions, and deduplicate records
- **Marts** that expose a star schema — one fact table and two dimension tables — ready for BI consumption
- **Reporting** aggregations built directly on top of the fact table for revenue analysis

---

## 2. Data Sources

### Primary Source — NYC TLC Trip Records

I source the raw data from the **[DataTalksClub NYC TLC Data repository](https://github.com/DataTalksClub/nyc-tlc-data)**, which mirrors the official NYC Taxi & Limousine Commission (TLC) trip records. This mirror is used for its reliability and the convenience of direct `.csv.gz` download links.

| Dataset | Coverage | Format | Rows (approx.) |
|---|---|---|---|
| **Yellow Taxi Trip Records** | Jan 2019 – Dec 2020 | Parquet (converted from CSV.gz) | ~84 million |
| **Green Taxi Trip Records** | Jan 2019 – Dec 2020 | Parquet (converted from CSV.gz) | ~8 million |

**Official upstream source:** [NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)

**Download base URL used by the ingestion script:**
```
https://github.com/DataTalksClub/nyc-tlc-data/releases/download
```

> **Note on Green vs. Yellow taxis:** Yellow taxis (`tpep_*` prefixed timestamps) primarily serve Manhattan. Green taxis (`lpep_*` prefixed timestamps — Licensed Passenger Enhancement Program) serve the outer boroughs. The staging models normalise these naming differences into a consistent schema.

### Reference / Seed Data

| Seed File | Description | Source |
|---|---|---|
| `taxi_zone_lookup.csv` | Maps 265 TLC Location IDs to borough, zone, and service zone | NYC TLC / NYC Dept. of City Planning NTAs |
| `payment_type_lookup.csv` | Maps payment type codes (1–6) to human-readable descriptions | NYC TLC Data Dictionary |

---

## 3. Tech Stack

| Tool | Version | Purpose |
|---|---|---|
| **dbt-core** | 1.12.2 | Data transformation framework |
| **dbt-duckdb** | 1.11.0 | dbt adapter for DuckDB |
| **DuckDB** | (embedded) | Local OLAP database engine |
| **dbt-utils** | 1.1.1 | Utility macros (e.g. `generate_surrogate_key`) |
| **Python** | 3.x | Data ingestion script |
| **Parquet** | — | Columnar file format for raw data storage |

---

## 4. Project Architecture

The pipeline follows the **medallion-style layered architecture** recommended by dbt Labs:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        INGESTION (Python)                           │
│  scripts/ingest_data.py                                             │
│  Downloads CSV.gz → converts to Parquet → loads into DuckDB        │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                SOURCE (DuckDB: taxi_rides_ny.duckdb)                │
│  prod.yellow_tripdata         prod.green_tripdata                   │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       STAGING (views)                               │
│  stg_yellow_tripdata   stg_green_tripdata                           │
│  · Rename columns  · Cast types  · Filter nulls                     │
│  · Generate surrogate trip ID                                       │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    INTERMEDIATE (views)                             │
│  int_trips_unioned → int_trips                                      │
│  · Union Green + Yellow  · Enrich payment descriptions              │
│  · Deduplicate with QUALIFY                                         │
└─────────────┬───────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       MARTS (tables)                                │
│  dim_zones   dim_vendors   fct_trips (incremental)                  │
│  reporting/fct_monthly_zone_revenue                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. Folder Structure

```
nyc_taxi_dbt/
│
├── dbt_project.yml           # Project name, profile, materialisation config
├── packages.yml              # dbt package dependencies (dbt_utils)
├── package-lock.yml          # Locked package versions
├── .gitignore                # Excludes data/, target/, .venv/, *.duckdb
│
├── scripts/
│   └── ingest_data.py        # Download CSV.gz → Parquet → load into DuckDB
│
├── data/                     # Git-ignored — generated by ingest_data.py
│   ├── yellow/               # yellow_tripdata_YYYY-MM.parquet (24 files, 2019-2020)
│   └── green/                # green_tripdata_YYYY-MM.parquet  (24 files, 2019-2020)
│
├── models/
│   ├── staging/
│   │   ├── sources.yml       # Source definitions & freshness thresholds
│   │   ├── stg_green_tripdata.sql
│   │   └── stg_yellow_tripdata.sql
│   │
│   ├── intermediate/
│   │   ├── schema.yml        # Column docs & data tests
│   │   ├── int_trips_unioned.sql
│   │   └── int_trips.sql
│   │
│   └── marts/
│       ├── schema.yml        # Column docs, data tests & model contract
│       ├── dim_zones.sql
│       ├── dim_vendors.sql
│       ├── fct_trips.sql     # Incremental fact table (merge strategy)
│       └── reporting/
│           └── fct_monthly_zone_revenue.sql
│
├── macros/
│   ├── macros_properties.yml
│   ├── get_trip_duration_minutes.sql
│   ├── get_vendor_data.sql
│   └── safe_cast.sql
│
├── seeds/
│   ├── seeds_properties.yml  # Seed documentation & tests
│   ├── taxi_zone_lookup.csv  # 265 TLC location zones
│   └── payment_type_lookup.csv  # 6 payment type codes
│
├── analyses/                 # Ad-hoc SQL analyses (not materialised)
├── snapshots/                # dbt snapshot definitions (future use)
├── tests/                    # Custom singular data tests
├── dbt_packages/             # Git-ignored — installed by `dbt deps`
├── target/                   # Git-ignored — compiled SQL & artefacts
├── logs/                     # Git-ignored — dbt run logs
└── .venv/                    # Git-ignored — Python virtual environment
```

---

## 6. Data Model

### Staging Layer

> **Materialisation:** `view`

Both staging models sit on top of the raw DuckDB source tables. Their responsibility is purely **type safety and naming consistency** — no business logic lives here.

#### `stg_yellow_tripdata`

| Column | Type | Source Column | Notes |
|---|---|---|---|
| `tripid` | string | `vendorid` + `tpep_pickup_datetime` | Surrogate key via `dbt_utils.generate_surrogate_key` |
| `vendor_id` | integer | `vendorid` | |
| `rate_code_id` | integer | `ratecodeid` | |
| `pickup_location_id` | integer | `pulocationid` | |
| `dropoff_location_id` | integer | `dolocationid` | |
| `pickup_datetime` | timestamp | `tpep_pickup_datetime` | TPEP = Taxicab Passenger Enhancement Program |
| `dropoff_datetime` | timestamp | `tpep_dropoff_datetime` | |
| `passenger_count` | integer | `passenger_count` | |
| `trip_distance` | numeric | `trip_distance` | Miles |
| `fare_amount` | numeric | `fare_amount` | |
| `total_amount` | numeric | `total_amount` | |
| `payment_type` | integer | `payment_type` | |
| *(+ other payment fields)* | | | |

**Filter applied:** Records where `vendorid IS NULL` are excluded.

#### `stg_green_tripdata`

Identical schema to `stg_yellow_tripdata` with two additions:

| Column | Type | Notes |
|---|---|---|
| `trip_type` | integer | 1 = Street-hail, 2 = Dispatch. Uses `safe_cast` macro |
| `ehail_fee` | numeric | E-hail surcharge (Green-taxi specific) |

**Filter applied:** Records where `vendorid IS NULL` are excluded.

---

### Intermediate Layer

> **Materialisation:** `view`

#### `int_trips_unioned`

Unions the two staging models into one normalised schema. Yellow trips get `ehail_fee = 0` and `trip_type = 1` applied for schema consistency. A `service_type` column (`'Green'` or `'Yellow'`) is added to preserve the origin.

> **Development limit:** This model currently applies `LIMIT 100000` to keep local development fast. Remove this limit for full production runs.

#### `int_trips`

Enriches `int_trips_unioned` with:

1. **A new surrogate key** — `trip_id` generated from `vendor_id`, `pickup_datetime`, `pickup_location_id`, and `service_type`
2. **Payment description** — joined from the `payment_type_lookup` seed
3. **Deduplication** — uses `QUALIFY row_number() OVER (PARTITION BY vendor_id, pickup_datetime, pickup_location_id, service_type ORDER BY dropoff_datetime) = 1` to remove duplicates

---

### Marts Layer

> **Materialisation:** `table` (except `fct_trips` which is `incremental`)

#### `dim_zones`

A pass-through dimension from the `taxi_zone_lookup` seed.

| Column | Type | Description |
|---|---|---|
| `location_id` | integer | PK — TLC Taxi Zone ID |
| `borough` | string | NYC borough (Manhattan, Brooklyn, Queens, Bronx, Staten Island, EWR) |
| `zone` | string | Neighbourhood zone name |
| `service_zone` | string | Yellow Zone, Boro Zone, or EWR |

#### `dim_vendors`

| Column | Type | Description |
|---|---|---|
| `vendor_id` | integer | PK |
| `vendor_name` | string | Company name resolved via `get_vendor_data` macro |

#### `fct_trips`

The core fact table. Uses an **incremental merge strategy** keyed on `trip_id`. A model contract enforces column data types.

| Column | Type | Description |
|---|---|---|
| `trip_id` | string | PK — surrogate key |
| `vendor_id` | integer | FK → `dim_vendors` |
| `service_type` | string | `'Green'` or `'Yellow'` |
| `rate_code_id` | integer | 1=Standard, 2=JFK, 3=Newark, etc. |
| `pickup_location_id` | integer | FK → `dim_zones` |
| `pickup_borough` | string | Denormalised from `dim_zones` |
| `pickup_zone` | string | Denormalised from `dim_zones` |
| `dropoff_location_id` | integer | FK → `dim_zones` |
| `dropoff_borough` | string | Denormalised from `dim_zones` |
| `dropoff_zone` | string | Denormalised from `dim_zones` |
| `pickup_datetime` | timestamp | |
| `dropoff_datetime` | timestamp | |
| `store_and_fwd_flag` | string | Y/N — trip stored in vehicle memory |
| `passenger_count` | integer | |
| `trip_distance` | numeric | Miles |
| `trip_type` | integer | 1=Street-hail, 2=Dispatch |
| `trip_duration_minutes` | bigint | Calculated by `get_trip_duration_minutes` macro |
| `fare_amount` | numeric | |
| `extra` | numeric | |
| `mta_tax` | numeric | |
| `tip_amount` | numeric | |
| `tolls_amount` | numeric | |
| `ehail_fee` | numeric | |
| `improvement_surcharge` | numeric | |
| `total_amount` | numeric | |
| `payment_type` | integer | |
| `payment_type_description` | string | Human-readable payment label |

---

### Reporting Layer

#### `fct_monthly_zone_revenue`

A pre-aggregated reporting table grouped by `pickup_zone`, `revenue_month`, and `service_type`. Designed for BI/dashboarding tools.

| Column | Description |
|---|---|
| `pickup_zone` | Taxi zone name |
| `revenue_month` | Month-truncated date |
| `service_type` | Green or Yellow |
| `revenue_monthly_fare` | Sum of fare amounts |
| `revenue_monthly_total_amount` | Sum of total charges |
| `total_monthly_trips` | Trip count |
| `avg_monthly_passenger_count` | Average passengers per trip |
| `avg_monthly_trip_distance` | Average trip distance (miles) |

---

## 7. Seeds & Reference Data

I use two seed files as static dimension tables that I version-control directly in the repo.

### `taxi_zone_lookup.csv`

- **265 rows**, one per TLC Taxi Zone
- Based on NYC Department of City Planning's Neighbourhood Tabulation Areas (NTAs)
- Columns: `LocationID`, `Borough`, `Zone`, `service_zone`
- Used in: `dim_zones.sql` and denormalised into `fct_trips.sql`

### `payment_type_lookup.csv`

- **6 rows**, one per payment method
- Columns: `payment_type` (1–6), `description`
- Used in: `int_trips.sql` for enrichment

| Code | Description |
|---|---|
| 1 | Credit card |
| 2 | Cash |
| 3 | No charge |
| 4 | Dispute |
| 5 | Unknown |
| 6 | Voided |

---

## 8. Custom Macros

I wrote three custom macros housed in `macros/`.

### `safe_cast(column_name, type)`

A safe wrapper around `TRY_CAST` that gracefully handles casting failures by returning `NULL` instead of raising an error. I use this for nullable integer columns in the green taxi staging model (`trip_type`, `payment_type`, `rate_code_id`).

```sql
-- Usage
{{ safe_cast('trip_type', 'integer') }}

-- Compiles to
TRY_CAST(trip_type AS integer)
```

### `get_vendor_data(vendor_id_column)`

Generates a `CASE` statement that maps vendor IDs to company names. I centralised this logic in a macro to avoid repetition across models.

```sql
-- Usage
{{ get_vendor_data('vendor_id') }}

-- Compiles to
CASE vendor_id
    WHEN 1 THEN 'Creative Mobile Technologies'
    WHEN 2 THEN 'VeriFone Inc.'
    ELSE 'Unknown'
END
```

### `get_trip_duration_minutes(pickup_column, dropoff_column)`

Calculates trip duration in minutes using DuckDB's `date_diff` function.

```sql
-- Usage
{{ get_trip_duration_minutes('trips.pickup_datetime', 'trips.dropoff_datetime') }}

-- Compiles to
date_diff('minute', trips.pickup_datetime, trips.dropoff_datetime)
```

---

## 9. Tests & Data Quality

I apply dbt's built-in generic tests and enforce a model contract on `fct_trips`.

### Generic Tests

| Model | Column | Tests |
|---|---|---|
| `int_trips` | `trip_id` | `unique`, `not_null` |
| `int_trips` | `vendor_id` | `not_null` |
| `int_trips` | `service_type` | `not_null`, `accepted_values: [Green, Yellow]` |
| `int_trips` | `pickup_datetime` | `not_null` |
| `int_trips` | `total_amount` | `not_null` |
| `dim_zones` | `location_id` | `unique`, `not_null` |
| `dim_vendors` | `vendor_id` | `unique`, `not_null` |
| `fct_trips` | `trip_id` | `unique`, `not_null` |
| `fct_trips` | `vendor_id` | `not_null` |
| `fct_trips` | `service_type` | `not_null`, `accepted_values` |
| `fct_trips` | `pickup_datetime` | `not_null` |
| `fct_trips` | `total_amount` | `not_null` |
| `fct_trips` | `pickup_location_id` | `relationships → dim_zones.location_id` |
| `fct_trips` | `dropoff_location_id` | `relationships → dim_zones.location_id` |
| `payment_type_lookup` | `payment_type` | `unique`, `not_null` |

### Source Freshness

Sources are configured with freshness thresholds on the `loaded_at_field`:

| Level | Threshold |
|---|---|
| Warning | Data older than 24 hours |
| Error | Data older than 48 hours |

```bash
dbt source freshness
```

---

## 10. Getting Started

### Prerequisites

- **Python 3.9+** — [Download here](https://www.python.org/downloads/)
- **pip** — Comes bundled with Python
- **git** — For cloning the repo

### Installation

**Step 1 — Clone the repository**

```bash
git clone <your-repository-url>
cd nyc_taxi_dbt
```

**Step 2 — Create and activate a Python virtual environment**

```bash
python -m venv .venv

# Linux / macOS
source .venv/bin/activate

# Windows
.venv\Scripts\activate
```

**Step 3 — Install dbt and the DuckDB adapter**

```bash
pip install dbt-core==1.12.2 dbt-duckdb==1.11.0
```

**Step 4 — Install Python dependencies for the ingestion script**

```bash
pip install duckdb requests
```

**Step 5 — Verify dbt installation**

```bash
dbt --version
```

Expected output:
```
Core:
  - installed: 1.12.2

Plugins:
  - duckdb: 1.11.0
```

**Step 6 — Configure the dbt profile**

dbt looks for a connection profile in `~/.dbt/profiles.yml`. Create it if it doesn't exist:

```yaml
# ~/.dbt/profiles.yml
nyc_taxi_dbt:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: /absolute/path/to/nyc_taxi_dbt/taxi_rides_ny.duckdb
```

Verify the connection:

```bash
dbt debug
```

---

### Running the Project Step by Step

> Run all commands from the project root with your virtual environment activated.

---

#### Step 1 — Ingest the raw data

```bash
python scripts/ingest_data.py
```

This script:
1. Downloads `.csv.gz` files from the DataTalksClub GitHub mirror
2. Converts each file to Parquet (via DuckDB) and deletes the intermediate `.csv.gz`
3. Creates `taxi_rides_ny.duckdb` with a `prod` schema
4. Loads all Parquet files into `prod.yellow_tripdata` and `prod.green_tripdata`
5. Updates `.gitignore` to exclude the `data/` directory

> **Expected time:** 15–60 minutes depending on internet speed. Total raw data is ~3 GB. Files are skipped if they already exist, so this script is safe to re-run.

---

#### Step 2 — Install dbt packages

```bash
dbt deps
```

Installs `dbt-labs/dbt_utils` (v1.1.1) into `dbt_packages/`.

---

#### Step 3 — Load seed data

```bash
dbt seed
```

Loads `taxi_zone_lookup.csv` and `payment_type_lookup.csv` into the DuckDB database as tables.

---

#### Step 4 — Run all dbt models

```bash
dbt run
```

Builds all models in dependency order:

```
stg_green_tripdata  ─┐
                      ├── int_trips_unioned ── int_trips ── fct_trips ── fct_monthly_zone_revenue
stg_yellow_tripdata ─┘                                   └── dim_vendors
                                                         (dim_zones from seed)
```

---

#### Step 5 — Run all data tests

```bash
dbt test
```

All tests should pass on a clean run.

---

#### Step 6 — (Optional) Generate and serve documentation

```bash
dbt docs generate
dbt docs serve
```

Opens an interactive data catalogue at `http://localhost:8080` with the full lineage DAG and column-level documentation.

---

#### Full pipeline — run everything at once

```bash
dbt deps && dbt seed && dbt run && dbt test
```

---

## 11. dbt Commands Reference

| Command | Description |
|---|---|
| `dbt deps` | Install packages from `packages.yml` |
| `dbt seed` | Load CSV seed files into the database |
| `dbt run` | Build all models |
| `dbt run --select staging` | Build only the staging layer |
| `dbt run --select marts` | Build only the marts layer |
| `dbt run --select fct_trips` | Build a single model |
| `dbt run --select +fct_trips` | Build `fct_trips` and all its upstream dependencies |
| `dbt run --full-refresh` | Rebuild incremental models from scratch |
| `dbt test` | Run all tests |
| `dbt test --select fct_trips` | Run tests for a specific model |
| `dbt source freshness` | Check if sources are within freshness thresholds |
| `dbt compile` | Compile Jinja SQL to raw SQL (without running) |
| `dbt docs generate` | Generate static documentation site |
| `dbt docs serve` | Serve docs locally at http://localhost:8080 |
| `dbt clean` | Remove `target/` and `dbt_packages/` directories |
| `dbt debug` | Validate project config and database connection |

---

## 12. Troubleshooting

### Profile not found

**Symptom:**
```
Runtime Error: Could not find profile named 'nyc_taxi_dbt'
```

**Fix:** Create `~/.dbt/profiles.yml` with the DuckDB connection (see Step 6 in Installation).

---

### Source table not found

**Symptom:**
```
Catalog Error: Table with name yellow_tripdata does not exist!
```

**Fix:** The raw data has not been ingested yet. Run the ingestion script first:
```bash
python scripts/ingest_data.py
```

---

### Ingestion script — network error / 404

**Symptom:**
```
requests.exceptions.HTTPError: 404 Client Error
```

**Fix:** Check your internet connection. If a specific month's file returns 404, verify the current URL structure on the [DataTalksClub releases page](https://github.com/DataTalksClub/nyc-tlc-data/releases).

---

### Unique test fails on `fct_trips` after re-runs

**Symptom:** The `unique` test on `trip_id` fails after multiple incremental runs.

**Fix:** Force a full rebuild of the fact table:
```bash
dbt run --select fct_trips --full-refresh
```

---

### Out of memory on large datasets

**Symptom:** DuckDB runs out of memory processing all 48 Parquet files.

**Fix 1:** The `int_trips_unioned` model includes `LIMIT 100000` for local development — this is intentional. Remove it only for full-scale production runs.

**Fix 2:** Increase DuckDB's memory limit in `~/.dbt/profiles.yml`:
```yaml
dev:
  type: duckdb
  path: taxi_rides_ny.duckdb
  settings:
    memory_limit: '8GB'
```

---

### `dbt docs serve` — port already in use

**Fix:** Use a different port:
```bash
dbt docs serve --port 8081
```

---

### Checking logs for more detail

All dbt run logs are written to `logs/dbt.log`. I always check this file first when debugging:

```bash
tail -100 logs/dbt.log
```

---

## Resources

- [dbt Documentation](https://docs.getdbt.com/docs/introduction)
- [dbt-duckdb Adapter](https://github.com/duckdb/dbt-duckdb)
- [DuckDB Documentation](https://duckdb.org/docs/)
- [NYC TLC Trip Record Data (Official)](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
- [DataTalksClub NYC TLC Data Mirror](https://github.com/DataTalksClub/nyc-tlc-data)
- [dbt-utils Package](https://hub.getdbt.com/dbt-labs/dbt_utils/latest/)
- [dbt Community Slack](https://community.getdbt.com/)
