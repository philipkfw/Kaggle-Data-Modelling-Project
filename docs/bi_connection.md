# Connecting a BI Tool

BI tools should connect **only to `KAGGLE_DB.GOLD`**. Silver is internal, and Bronze is raw.

## 1. Connect to Snowflake
Most BI tools ship with a native Snowflake connector. Use these connection details:
- **Server:** `<ORGNAME-ACCOUNTNAME>.snowflakecomputing.com`
- **Role:** a read-only reporting role (see §4), or `SYSADMIN` for local testing.
- **Warehouse:** `COMPUTE_WH`
- **Database / schema:** `KAGGLE_DB` / `GOLD`
- **Authentication:** username + password (with MFA), key pair, or SSO.

The data is static, so cached or extract-style connections give the fastest dashboards, if your tool supports them.

## 2. Which tables to use

| Question | Table | Notes |
|---|---|---|
| GPV and invoice trends by segment | `mart_financial_performance` | Fully additive; slice by any dimension |
| Account stage distribution over time | `mart_account_lifecycle` | Stocks are semi-additive (see below) |
| Monthly executive dashboard | `mart_account_performance` | One row per month × segment |
| Trial conversion cohorts | `dim_accounts` | Group by `trial_started_date_mt` (month) |
| Drill to individual invoices or payments | `fct_invoices` / `fct_payment_transactions` + `dim_accounts` | Join on `account_id`; never join the two facts to each other |
| Audit a USD conversion | `dim_fx_rates` | Join on (`rate_date`, `from_currency`) |

Each mart is self-contained, so **no joins are needed** for the standard metrics.

## 3. Calculations

The examples below are SQL. The same logic carries over to any BI tool's calculated fields.

### Stocks (account counts): take the last date of each period, never SUM over time
Choose one:
- **Monthly or longer trends:** use `mart_account_performance`. It already exposes month-end values (`*_eom`), so a plain `SUM` across segments is correct.
- **Point in time:** filter `mart_account_lifecycle` to a single `reporting_date`, then `SUM` across segments.
- **Daily trend lines:** plot `reporting_date` at day level. Each point is a single day, so nothing is summed across dates.

Avoid rolling `reporting_date` up to month or quarter and summing a stock column; that adds up the daily balances.

```sql
-- Accounts by stage on a given date, split by country
SELECT
    country
    ,SUM(trial_accounts) AS trial_accounts
    ,SUM(subscribed_accounts) AS subscribed_accounts
    ,SUM(churned_accounts) AS churned_accounts
FROM KAGGLE_DB.GOLD.mart_account_lifecycle
WHERE reporting_date = '2024-09-30'
GROUP BY country
```

### Trial conversion rate (from `dim_accounts`)
```sql
SELECT
    DATE_TRUNC('MONTH', trial_started_date_mt) AS trial_cohort_month
    ,COUNT(account_id) AS trial_accounts
    ,COUNT_IF(has_converted_within_window) AS converted_within_90_days
    ,COUNT_IF(has_converted_within_window) / COUNT(account_id) AS trial_conversion_rate
FROM KAGGLE_DB.GOLD.dim_accounts
-- Only trials that have had the full 90-day window (reporting end date minus 90 days)
WHERE trial_started_date_mt <= '2025-05-14'
GROUP BY trial_cohort_month
ORDER BY trial_cohort_month
```

### Monthly churn rate (from `mart_account_performance`)
```sql
WITH monthly AS (

    SELECT
        month_start_date
        ,SUM(new_churns) AS new_churns
        ,SUM(subscribed_accounts_eom) AS subscribed_accounts_eom
    FROM KAGGLE_DB.GOLD.mart_account_performance
    GROUP BY month_start_date

)

SELECT
    month_start_date
    ,new_churns
    -- Denominator: subscribers at the start of the month = previous month's closing balance
    ,new_churns / NULLIF(LAG(subscribed_accounts_eom) OVER (ORDER BY month_start_date), 0) AS churn_rate
FROM monthly
ORDER BY month_start_date
```

### Electronic share of GPV
```sql
SELECT
    SUM(gpv_electronic_usd) / SUM(gpv_usd) AS electronic_gpv_share
FROM KAGGLE_DB.GOLD.mart_financial_performance
```

## 4. Recommended reporting role
```sql
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS REPORTER;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE REPORTER;
GRANT USAGE ON DATABASE KAGGLE_DB TO ROLE REPORTER;
GRANT USAGE ON SCHEMA KAGGLE_DB.GOLD TO ROLE REPORTER;
GRANT SELECT ON ALL TABLES IN SCHEMA KAGGLE_DB.GOLD TO ROLE REPORTER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA KAGGLE_DB.GOLD TO ROLE REPORTER;
GRANT ROLE REPORTER TO USER <bi_service_user>;
```
`SECURITYADMIN` holds `MANAGE GRANTS`, so it can run every statement above. Gold tables are rebuilt with `CREATE OR REPLACE` on each `dbt build`, and the future grant is what keeps access in place afterwards.
