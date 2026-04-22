# Banking DBT Pipeline

A production-ready data pipeline framework inspired by **Avaloq/Azqore core banking architecture**, built with DBT and Snowflake. Designed to be adapter to any core banking system (Avaloq, Temenos, Murex, etc).

---

## Overview

This project replicates the data architecture used in Swiss private banking institutions, covering the full pipeline from raw core banking extracts to business-ready reporting tables.

**Key capabilities:**
- Full historization of client and portfolio dimensions (SCD Type 2)
- Banking calendar with end-of-month positions
- Forward fill of positions across time periods
- Multi-currency exposure calculation
- Production-ready on **Snowflake** with local development on **DuckDB**

---

## Architecture

```
ST0 (Raw Avaloq extracts)
    ↓
Staging (Cleaning, renaming, casting)
    ↓
Intermediate (Business logic, historization, calendar join)
    ↓
Marts (Business-ready reporting tables)
```

### Layer Details

| Layer | Models | Description |
|---|---|---|
| **Seeds** | `st0_*` | Raw core banking data (clients, portfolios, positions, FX rates) |
| **Staging** | `stg_*` | Cleaned and typed models, calendar generation |
| **Snapshots** | `clients_snapshot`, `portfolio_snapshot` | SCD Type 2 historization via DBT snapshots |
| **Intermediate** | `int_*` | Calendar × dimensions cross join, position enrichment |
| **Marts** | `mart_*` | Client exposure, portfolio performance |

---

## Data Model

### Seeds (ST0 — Raw Avaloq layer)
- `st0_dim_cli` — Client master data
- `st0_dim_ptf` — Portfolio master data  
- `st0_fct_ast` — Pre-calculated positions (Avaloq output)
- `st0_fct_ope` — Financial operations (BUY/SELL)
- `st0_fct_xrt` — FX rates
- `st0_fct_xrt_prices` — Market prices

### Staging
- `stg_dim_cli` — Cleaned client dimension
- `stg_dim_ptf` — Cleaned portfolio dimension
- `stg_fct_ast` — Cleaned position facts
- `stg_fct_ope` — Cleaned operations
- `stg_set_cal` — Dynamic banking calendar (month-end dates from 2024 to today)

### Snapshots
- `clients_snapshot` — Full client history with `dbt_valid_from` / `dbt_valid_to`
- `portfolio_snapshot` — Full portfolio history

### Intermediate
- `int_dim_cli` — Client dimension × banking calendar (one row per client per month)
- `int_dim_ptf` — Portfolio dimension × banking calendar
- `int_fct_ast` — Positions enriched with client hierarchy
- `int_ptf_idx` — Central index: portfolios × calendar × positions with forward fill

### Marts
- `mart_portfolio_performance` — Portfolio valuation with FX conversion
- `mart_client_exposure` — Client exposure by asset with FX conversion to base currency

---

## Key Technical Concepts

### Banking Calendar
End-of-month dates from January 2024 to today. The current month uses today's date rather than projecting a future month-end — consistent with how banks report intra-month positions.

### SCD Type 2 Historization
Client and portfolio dimensions are fully historized using DBT snapshots. Each attribute change (category, RM, risk profile) creates a new version with `dbt_valid_from` / `dbt_valid_to` timestamps — equivalent to `VR_DWH_BEG` / `VR_DWH_END` in Avaloq's native DWH architecture.

### Forward Fill of Positions
Avaloq delivers positions at month-end. The intermediate layer propagates the last known position to all subsequent calendar dates until a new position is received — using `ASOF JOIN` on DuckDB and correlated subqueries on Snowflake.

### Multi-Currency Support
FX rates are applied to convert positions to a base currency (USD), with the last known rate propagated forward when no new rate is available for a given date.

---

## 🛠️ Tech Stack

| Tool | Usage |
|---|---|
| **DBT Core** | Data transformation framework |
| **Snowflake** | Production data warehouse |
| **DuckDB** | Local development |
| **dbt-utils** | Additional test macros |
| **SQLFluff** | SQL linting and formatting |

---

## Data Quality

**37 data tests** covering:
- `not_null` on all critical columns
- `unique` on primary keys
- `accepted_values` on business codes (BUY/SELL, PRIVATE/RETAIL, GROWTH/BALANCED/CONSERV)
- `relationships` for referential integrity across dimensions

---

## Getting Started

### Prerequisites
- Python 3.9+
- DBT Core 1.10+

### Local Development (DuckDB)

```bash
# Clone the repository
git clone https://github.com/ThouvenotJeremy/banking-dbt-pipeline.git
cd banking-dbt-pipeline/banking_pipeline

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install dbt-core dbt-duckdb sqlfluff sqlfluff-templater-dbt

# Run the full pipeline
dbt seed
dbt snapshot
dbt run
dbt test
```

### Production (Snowflake)

Add a `prod` target to your `profiles.yml`:

```yaml
banking_pipeline:
  outputs:
    dev:
      type: duckdb
      path: dev.duckdb
      threads: 1
    prod:
      type: snowflake
      account: YOUR_ACCOUNT
      user: YOUR_USER
      password: YOUR_PASSWORD
      role: ACCOUNTADMIN
      database: BANKING_DBT
      warehouse: COMPUTE_WH
      schema: PUBLIC
      threads: 4
  target: dev
```

```bash
dbt seed --target prod
dbt snapshot --target prod
dbt run --target prod
dbt test --target prod
```

---

## 📁 Project Structure

```
banking_pipeline/
├── models/
│   ├── staging/
│   │   ├── stg_dim_cli.sql
│   │   ├── stg_dim_ptf.sql
│   │   ├── stg_fct_ast.sql
│   │   ├── stg_fct_ope.sql
│   │   ├── stg_set_cal.sql
│   │   ├── sources.yml
│   │   └── schema.yml
│   ├── intermediate/
│   │   ├── int_dim_cli.sql
│   │   ├── int_dim_ptf.sql
│   │   ├── int_fct_ast.sql
│   │   ├── int_ptf_idx.sql
│   │   └── schema.yml
│   └── marts/
│       ├── mart_portfolio_performance.sql
│       └── mart_client_exposure.sql
├── snapshots/
│   ├── clients_snapshot.sql
│   └── portfolio_snapshot.sql
├── seeds/
│   ├── st0_dim_cli.csv
│   ├── st0_dim_ptf.csv
│   ├── st0_fct_ast.csv
│   ├── st0_fct_ope.csv
│   ├── st0_fct_xrt.csv
│   └── st0_fct_xrt_prices.csv
├── dbt_project.yml
├── packages.yml
└── profiles.yml
```

---

## Author

**Jérémy Thouvenot** — Data & BI Consultant  
5 years in Swiss private banking (Lombard Odier, CA Indosuez, Capital Union Bank, Hinduja Bank)  
Expert in Avaloq/Azqore data pipelines, Talend, Qlik Sense, Power BI

[Malt Profile](https://www.malt.fr/profile/jeremythouvenot) | [LinkedIn](https://www.linkedin.com/in/jeremy-thouvenot/)