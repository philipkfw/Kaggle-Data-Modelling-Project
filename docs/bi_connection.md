# Connecting a BI Tool (Tableau)

BI tools should connect **only to `KAGGLE_DB.GOLD`**. Silver is internal, and Bronze is raw.

## 1. Connect Tableau to Snowflake
1. **Connect → To a Server → Snowflake.**
2. Fill in the connection details:
   - **Server:** `<ORGNAME-ACCOUNTNAME>.snowflakecomputing.com`
   - **Role:** a read-only reporting role (see §4), or `SYSADMIN` for local testing.
   - **Warehouse:** `COMPUTE_WH`
   - **Authentication:** username + password (with MFA), key pair, or SSO.
3. Choose **Database `KAGGLE_DB` → Schema `GOLD`**.
4. Use an **extract** connection: the data is static, so extracts give the fastest dashboards.

## 2. Which tables to use

| Question | Table | Notes |
|---|---|---|
| GPV and invoice trends by segment | `mart_financial_performance` | Fully additive; drag any dimension |
| Account stage distribution over time | `mart_account_lifecycle` | Stocks are semi-additive (see below) |
| Monthly executive dashboard | `mart_account_performance` | One row per month × segment |
| Trial conversion cohorts | `dim_accounts` | Group by `trial_started_date_mt` (month) |
| Drill to individual invoices or payments | `fct_invoices` / `fct_payment_transactions` + `dim_accounts` | Join on `account_id`; never join the two facts to each other |
| Audit a USD conversion | `dim_fx_rates` | Join on (`rate_date`, `from_currency`) |

Each mart is self-contained, so **no joins are needed** for the standard metrics.

## 3. Calculations

**Stocks (account counts): take the last date of each period, never SUM over time**

Choose one:
- **Monthly or longer trends:** use `mart_account_performance`. It already exposes month-end values (`*_eom`), so a plain `SUM` across segments is correct.
- **Point in time:** filter `mart_account_lifecycle.reporting_date` to a single date, e.g. the reporting end date, then `SUM` across segments.
- **Daily trend lines:** put `reporting_date` (exact date) on Columns and `SUM([Subscribed Accounts])` on Rows. Each mark is a single day, so nothing is summed across dates.

Avoid putting `reporting_date` at month or quarter level with `SUM` of a stock column; that adds up the daily balances.

**Trial conversion rate** (from `dim_accounts`)
```
SUM(IIF([Has Converted Within Window], 1, 0)) / COUNT([Account Id])
// Columns: DATETRUNC('month', [Trial Started Date Mt])
// Exclude trials started after 2025-05-14 (reporting end date minus the 90-day window)
```

**Monthly churn rate** (from `mart_account_performance`, months on Columns)
```
SUM([New Churns]) / LOOKUP(SUM([Subscribed Accounts Eom]), -1)
```

**Electronic share of GPV**
```
SUM([Gpv Electronic Usd]) / SUM([Gpv Usd])
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
GRANT ROLE REPORTER TO USER <tableau_service_user>;
```
`SECURITYADMIN` holds `MANAGE GRANTS`, so it can run every statement above. Gold tables are rebuilt with `CREATE OR REPLACE` on each `dbt build`, and the future grant is what keeps access in place afterwards.
