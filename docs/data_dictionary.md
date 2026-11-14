# Data Dictionary

Generated from dbt metadata by `scripts/generate_data_dictionary.py`. Do not edit by hand; update the model YAML files and regenerate. Types are the actual Snowflake column types.

## Gold – Reporting Marts

### `mart_account_lifecycle`

**Location:** `KAGGLE_DB.GOLD.MART_ACCOUNT_LIFECYCLE`

Grain: one row per reporting date (MT) x country x region x city x sign-up platform, dense from each segment's first sign-up. STOCKS (*_accounts) are point-in-time counts at end of day: they can be summed across segments but must NEVER be summed across dates; use the last date of the period. FLOWS (new_*) count events on the date and are fully additive.

| Column | Type | Description |
|---|---|---|
| `reporting_date` | DATE | Snapshot date (end of day, Mountain Time). |
| `country` | TEXT | Account country. |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. |
| `region` | TEXT | Account region. |
| `city` | TEXT | Account city. |
| `sign_up_platform` | TEXT | Account sign-up platform. |
| `pre_trial_accounts` | NUMBER | STOCK. Accounts signed up but with no trial event yet, at end of day. |
| `trial_accounts` | NUMBER | STOCK. Accounts in trial at end of day. |
| `subscribed_accounts` | NUMBER | STOCK. Accounts subscribed at end of day. |
| `churned_accounts` | NUMBER | STOCK. Accounts churned at end of day (cumulative; churn is a terminal state). |
| `total_accounts` | NUMBER | STOCK. All accounts signed up by end of day (sum of the four stages). |
| `new_sign_ups` | NUMBER | FLOW. Accounts that signed up on the date. |
| `new_trials` | NUMBER | FLOW. Accounts that started a trial on the date. |
| `new_subscriptions` | NUMBER | FLOW. Accounts that subscribed on the date. |
| `new_churns` | NUMBER | FLOW. Accounts that churned on the date. |

### `mart_account_performance`

**Location:** `KAGGLE_DB.GOLD.MART_ACCOUNT_PERFORMANCE`

Grain: one row per month x country x region x city x sign-up platform. Executive view combining lifecycle and financial metrics, each rolled up to this grain independently before joining. Stocks (*_eom) are as of the month's last reporting date and must not be summed across months. Flows and financials are monthly totals. Trial conversion is analysed at account level from dim_accounts (trial_started_date_mt, has_converted_within_window).

| Column | Type | Description |
|---|---|---|
| `month_start_date` | DATE | First day of the reporting month. |
| `month_reporting_end_date` | DATE | Last date with data in the month (stocks are measured on this date). |
| `is_partial_month` | BOOLEAN | TRUE if the month extends past the reporting end date. |
| `country` | TEXT | Account country. |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. |
| `region` | TEXT | Account region. |
| `city` | TEXT | Account city. |
| `sign_up_platform` | TEXT | Account sign-up platform. |
| `pre_trial_accounts_eom` | NUMBER | STOCK. Pre-trial accounts at month end. |
| `trial_accounts_eom` | NUMBER | STOCK. Trial accounts at month end. |
| `subscribed_accounts_eom` | NUMBER | STOCK. Subscribed accounts at month end. |
| `churned_accounts_eom` | NUMBER | STOCK. Churned accounts at month end (cumulative). |
| `total_accounts_eom` | NUMBER | STOCK. All signed-up accounts at month end. |
| `new_sign_ups` | NUMBER | FLOW. Sign-ups during the month. |
| `new_trials` | NUMBER | FLOW. Trials started during the month. |
| `new_subscriptions` | NUMBER | FLOW. Subscriptions during the month. |
| `new_churns` | NUMBER | FLOW. Churns during the month. |
| `gpv_usd` | NUMBER | Gross Payment Volume (USD) during the month. |
| `gpv_electronic_usd` | NUMBER | Electronic GPV (USD) during the month. |
| `gpv_offline_usd` | NUMBER | Offline (cash, cheque) GPV (USD) during the month. |
| `payment_count` | NUMBER | Payments during the month. |
| `invoice_count` | NUMBER | Invoice Volume during the month. |
| `invoice_amount_usd` | NUMBER | Invoice Dollar Volume (USD) during the month. |

### `mart_financial_performance`

**Location:** `KAGGLE_DB.GOLD.MART_FINANCIAL_PERFORMANCE`

Grain: one row per reporting date (MT) x country x region x city x sign-up platform, for combinations with any payment or invoice activity (sparse). Payments and invoices are aggregated independently, then combined on identical keys. GPV is dated by transaction date; invoice metrics by invoice created date. All measures are fully additive across every dimension and across dates.

| Column | Type | Description |
|---|---|---|
| `reporting_date` | DATE | Activity date, Mountain Time. |
| `country` | TEXT | Account country. |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. |
| `region` | TEXT | Account region. |
| `city` | TEXT | Account city. |
| `sign_up_platform` | TEXT | Account sign-up platform. |
| `gpv_usd` | NUMBER | Gross Payment Volume in USD (all payment methods), converted at transaction-date FX rates. |
| `gpv_electronic_usd` | NUMBER | GPV from electronic payments (Credit Card, ACH, Paypal). |
| `gpv_offline_usd` | NUMBER | GPV from offline payments (Cash, Cheque). |
| `payment_count` | NUMBER | Number of payment transactions. |
| `invoice_count` | NUMBER | Invoice Volume - number of distinct invoices created. |
| `invoice_amount_usd` | NUMBER | Invoice Dollar Volume in USD, converted at invoice-created-date FX rates. |

## Gold – Facts

### `fct_account_daily_status`

**Location:** `KAGGLE_DB.GOLD.FCT_ACCOUNT_DAILY_STATUS`

Grain: one row per account per calendar date (MT), from sign-up date to the reporting end date. Each account's lifecycle stage at end of day (Mountain Time), derived from fct_account_lifecycle intervals. Exactly one stage per account per day, so stage counts never double-count. Authoritative source for point-in-time (historical) account counts.

| Column | Type | Description |
|---|---|---|
| `account_daily_status_id` | TEXT | Surrogate key = hash(account_id, status_date). Primary key. |
| `status_date` | DATE | Calendar date (Mountain Time) the status applies to, as of end of day. |
| `account_id` | TEXT |  |
| `lifecycle_stage` | TEXT | End-of-day lifecycle stage. pre_trial = signed up but no trial event yet. |
| `lifecycle_event_id` | TEXT | Lifecycle event (interval) in effect at end of day. NULL while pre_trial. |
| `is_pre_trial` | NUMBER | 1 if pre_trial at end of day, else 0. |
| `is_trial` | NUMBER | 1 if in trial at end of day, else 0. |
| `is_subscribed` | NUMBER | 1 if subscribed at end of day, else 0. |
| `is_churned` | NUMBER | 1 if churned at end of day, else 0. |

### `fct_account_lifecycle`

**Location:** `KAGGLE_DB.GOLD.FCT_ACCOUNT_LIFECYCLE`

Grain: one row per account lifecycle event, which is also one effective-dated interval [valid_from_mt, valid_to_mt). Authoritative source for lifecycle flows (new trials, subscriptions, churns) and for an account's state at any point in time.

| Column | Type | Description |
|---|---|---|
| `lifecycle_event_id` | TEXT | Surrogate key = hash(account_id, event_time). Primary key. |
| `account_id` | TEXT |  |
| `event_sequence` | NUMBER | Chronological order of the event within the account (1 = first). |
| `lifecycle_state` | TEXT | State the account entered at this event. |
| `previous_lifecycle_state` | TEXT | State before this event (NULL for the first event). |
| `next_lifecycle_state` | TEXT | State after this interval ends (NULL if current). |
| `event_at_mt` | TIMESTAMP_NTZ | Event timestamp, Mountain Time. |
| `event_date_mt` | DATE | Event date, Mountain Time. Reporting date for lifecycle flows. |
| `valid_from_mt` | TIMESTAMP_NTZ | Interval start (inclusive), Mountain Time. |
| `valid_to_mt` | TIMESTAMP_NTZ | Interval end (exclusive), Mountain Time. NULL for the current interval. |
| `is_current` | BOOLEAN | TRUE for the account's current (open) interval. |
| `is_valid_transition` | BOOLEAN | FALSE if the transition is not (start)->trial, trial->subscribed or subscribed->churned. |
| `days_in_state` | NUMBER | Days spent in the state (to the reporting end date if current). |

### `fct_invoices`

**Location:** `KAGGLE_DB.GOLD.FCT_INVOICES`

Grain: one row per invoice. Authoritative source for Invoice Volume (COUNT DISTINCT invoice_id) and Invoice Dollar Volume (SUM invoice_amount_usd), both dated by invoice_created_date_mt. Join to dim_accounts on account_id for segmentation. Never join directly to fct_payment_transactions.

| Column | Type | Description |
|---|---|---|
| `invoice_id` | TEXT | Invoice identifier. Primary key. |
| `account_id` | TEXT | Account that issued the invoice. |
| `invoice_created_at_mt` | TIMESTAMP_NTZ | Invoice creation timestamp, Mountain Time. |
| `invoice_created_date_mt` | DATE | Invoice creation date, Mountain Time. Reporting date for invoice metrics and the FX conversion date. |
| `invoice_sent_at_mt` | TIMESTAMP_NTZ | Invoice sent timestamp, Mountain Time. |
| `invoice_sent_date_mt` | DATE | Invoice sent date, Mountain Time. |
| `invoice_amount` | NUMBER | Invoice amount in the original currency (major units). |
| `currency_code` | TEXT | Original invoice currency (ISO-4217). |
| `exchange_rate` | NUMBER | USD per 1 unit of currency_code, applied for invoice_created_date_mt. |
| `fx_rate_effective_date` | DATE | Publication date of the applied FX rate. |
| `fx_rate_source` | TEXT | Provider of the applied FX rate. |
| `invoice_amount_usd` | NUMBER | invoice_amount x exchange_rate. Unrounded. |
| `line_item_count` | NUMBER | Number of line items on the invoice. |
| `line_item_amount_total` | NUMBER | Sum of line item amounts (original currency). |
| `distinct_service_type_count` | NUMBER | Number of distinct service types on the invoice. |
| `is_amount_reconciled` | BOOLEAN | TRUE when invoice_amount equals line_item_amount_total. |
| `payment_count` | NUMBER | Number of payments recorded against the invoice. |
| `is_paid` | BOOLEAN | TRUE if at least one payment exists. The source has no invoice status, so unpaid can't be split into outstanding vs. void. |
| `lifecycle_stage_at_invoice` | TEXT | The account's lifecycle stage when the invoice was created. |
| `is_post_churn_activity` | BOOLEAN | Data quality flag. TRUE if the invoice was created after the account churned. Included in all metrics. |

### `fct_payment_transactions`

**Location:** `KAGGLE_DB.GOLD.FCT_PAYMENT_TRANSACTIONS`

Grain: one row per payment transaction. Authoritative source for Gross Payment Volume (SUM amount_usd), dated by transaction_date_mt. Includes all payment methods; payment_channel separates electronic from offline (cash, cheque) volume. The source has no refund or failure status, so no transactions are excluded.

| Column | Type | Description |
|---|---|---|
| `transaction_id` | TEXT | Payment transaction identifier. Primary key. |
| `account_id` | TEXT | Account that received the payment. |
| `invoice_id` | TEXT | Invoice the payment was made against. |
| `transaction_at_mt` | TIMESTAMP_NTZ | Payment timestamp, Mountain Time. |
| `transaction_date_mt` | DATE | Payment date, Mountain Time. Reporting date for GPV and the FX conversion date. |
| `payment_method` | TEXT | Payment method as recorded in the source. |
| `payment_channel` | TEXT | electronic (Credit Card, ACH, Paypal) or offline (Cash, Cheque). |
| `payment_amount` | NUMBER | Payment amount in the original currency (major units). |
| `currency_code` | TEXT | Original payment currency (ISO-4217). |
| `exchange_rate` | NUMBER | USD per 1 unit of currency_code, applied for transaction_date_mt. |
| `fx_rate_effective_date` | DATE | Publication date of the applied FX rate. |
| `fx_rate_source` | TEXT | Provider of the applied FX rate. |
| `amount_usd` | NUMBER | payment_amount x exchange_rate. Unrounded. GPV = SUM(amount_usd). |
| `lifecycle_stage_at_payment` | TEXT | The account's lifecycle stage when the payment was made. |
| `is_post_churn_activity` | BOOLEAN | Data quality flag. TRUE if the payment occurred after the account churned. Included in GPV. |

## Gold – Dimensions

### `dim_accounts`

**Location:** `KAGGLE_DB.GOLD.DIM_ACCOUNTS`

Grain: one row per account, with current attributes as of the reporting end date. The segmentation dimension (country, region, city, sign-up platform) for every fact and mart. Lifecycle milestone columns support account-level trial conversion analysis. Historical lifecycle state is NOT stored here; see fct_account_lifecycle and fct_account_daily_status.

| Column | Type | Description |
|---|---|---|
| `account_id` | TEXT | Account identifier. Primary key. |
| `sign_up_at_mt` | TIMESTAMP_NTZ | Sign-up timestamp, Mountain Time. |
| `sign_up_date_mt` | DATE | Sign-up date, Mountain Time. |
| `sign_up_platform` | TEXT | Platform the account signed up on. |
| `country` | TEXT | Country as recorded in the source ('Unknown' if geography is missing). |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. |
| `region` | TEXT | Region (territory-style; not strictly nested with city). |
| `city` | TEXT | City. |
| `has_geography` | BOOLEAN | FALSE if the account had no geography record. |
| `current_lifecycle_stage` | TEXT | Lifecycle stage as of the reporting end date. pre_trial = signed up but no trial event yet. |
| `current_stage_started_at_mt` | TIMESTAMP_NTZ | When the account entered its current stage (sign-up time for pre_trial). |
| `trial_started_at_mt` | TIMESTAMP_NTZ | Trial start timestamp, Mountain Time. |
| `trial_started_date_mt` | DATE | Trial start date, Mountain Time. Defines the trial conversion cohort. |
| `subscribed_at_mt` | TIMESTAMP_NTZ | Subscription timestamp, Mountain Time. NULL if never subscribed. |
| `subscribed_date_mt` | DATE | Subscription date, Mountain Time. |
| `churned_at_mt` | TIMESTAMP_NTZ | Churn timestamp, Mountain Time. NULL if never churned. |
| `churned_date_mt` | DATE | Churn date, Mountain Time. |
| `days_sign_up_to_trial` | NUMBER | Days from sign-up to trial start. |
| `days_trial_to_subscribed` | NUMBER | Days from trial start to subscription. |
| `days_subscribed_to_churned` | NUMBER | Days from subscription to churn. |
| `has_converted` | BOOLEAN | TRUE if the account ever moved from trial to subscribed. |
| `has_converted_within_window` | BOOLEAN | TRUE if the account subscribed within trial_conversion_window_days (90) of trial start. |
| `is_stale_trial` | BOOLEAN | Data quality flag. TRUE if the account is still in trial more than stale_trial_days (90) after trial start. The source has no trial-expiry event, so these accounts are reported as trial, exactly as recorded. |
| `lifecycle_event_count` | NUMBER | Number of lifecycle events recorded for the account. |

### `dim_date`

**Location:** `KAGGLE_DB.GOLD.DIM_DATE`

Grain: one row per calendar date (Mountain Time) from reporting_start_date to reporting_end_date. Date spine for point-in-time snapshots and a standard calendar dimension for BI.

| Column | Type | Description |
|---|---|---|
| `date_day` | DATE | Calendar date. Primary key. |
| `day_of_week_iso` | NUMBER | ISO day of week (1 = Monday, 7 = Sunday). |
| `day_name` | TEXT | Abbreviated day name. |
| `is_weekend` | BOOLEAN | TRUE on Saturday and Sunday. |
| `week_start_date` | DATE | Monday of the ISO week. |
| `month_start_date` | DATE | First day of the month. |
| `month_end_date` | DATE | Last calendar day of the month. |
| `month_reporting_end_date` | DATE | Last date with data in the month (the reporting end date for a partial final month). |
| `month_name` | TEXT | Abbreviated month name. |
| `year_month` | TEXT | YYYY-MM label. |
| `quarter_start_date` | DATE | First day of the quarter. |
| `quarter_number` | NUMBER | Quarter of the year (1-4). |
| `year_number` | NUMBER | Calendar year. |
| `is_month_end` | BOOLEAN | TRUE on the last calendar day of the month. |

### `dim_fx_rates`

**Location:** `KAGGLE_DB.GOLD.DIM_FX_RATES`

Grain: one row per calendar date per currency. The exact rates applied to every invoice and payment, so any USD amount can be audited back to its rate. Convention: 1 unit of from_currency = exchange_rate USD.

| Column | Type | Description |
|---|---|---|
| `fx_rate_id` | TEXT | Surrogate key = hash(rate_date, from_currency). |
| `rate_date` | DATE | Calendar date the rate applies to. |
| `from_currency` | TEXT | Original currency (ISO-4217). |
| `to_currency` | TEXT | Always USD. |
| `exchange_rate` | NUMBER | USD value of 1 unit of from_currency. |
| `rate_effective_date` | DATE | Publication date of the applied rate (latest on or before rate_date). |
| `days_since_published` | NUMBER | Days the applied rate has been carried forward (weekends and holidays). |
| `source_series_id` | TEXT | FRED series identifier (NULL for USD). |
| `rate_source` | TEXT | Federal Reserve H.10 via FRED, or identity for USD. |
| `rate_type` | TEXT | Rate methodology. |
| `loaded_at` | TIMESTAMP_NTZ | Date the rates were retrieved. |

## Silver – Intermediate

### `int_account_lifecycle`

**Location:** `KAGGLE_DB.SILVER.INT_ACCOUNT_LIFECYCLE`

Grain: one row per account lifecycle event. Sequences events chronologically, adds previous and next states, and turns each event into an effective-dated interval [valid_from, valid_to). The current state is the open interval (valid_to IS NULL). History is never overwritten.

| Column | Type | Description |
|---|---|---|
| `lifecycle_event_id` | TEXT | Surrogate key = hash(account_id, event_time). |
| `account_id` | TEXT | Account the event belongs to. |
| `event_sequence` | NUMBER | 1-based chronological order of the event within the account (tie-break by state rank). |
| `lifecycle_state` | TEXT | State the account entered at this event. |
| `previous_lifecycle_state` | TEXT | State before this event (NULL for the first event). |
| `next_lifecycle_state` | TEXT | State after this interval ends (NULL if current). |
| `event_at_utc` | TIMESTAMP_NTZ | Event timestamp (assumed UTC). |
| `event_at_mt` | TIMESTAMP_NTZ | Event timestamp in Mountain Time. |
| `event_date_mt` | DATE | Event date in Mountain Time. |
| `valid_from_utc` | TIMESTAMP_NTZ | Interval start (UTC). Used for point-in-time joins because UTC is strictly ordered. |
| `valid_to_utc` | TIMESTAMP_NTZ | Interval end, exclusive (UTC). NULL for the current interval. |
| `valid_from_mt` | TIMESTAMP_NTZ | Interval start in Mountain Time. |
| `valid_to_mt` | TIMESTAMP_NTZ | Interval end (exclusive) in Mountain Time. NULL for the current interval. |
| `is_current` | BOOLEAN | TRUE for the account's latest lifecycle event. |
| `is_valid_transition` | BOOLEAN | FALSE if the transition is not (start)->trial, trial->subscribed or subscribed->churned. |
| `days_in_state` | NUMBER | Days spent in the state (to the reporting end date if current). |

### `int_accounts_enriched`

**Location:** `KAGGLE_DB.SILVER.INT_ACCOUNTS_ENRICHED`

Grain: one row per account. Accounts LEFT JOIN geography; any missing geography is labelled 'Unknown' explicitly instead of dropping the account.

| Column | Type | Description |
|---|---|---|
| `account_id` | TEXT | Account identifier. |
| `sign_up_at_utc` | TIMESTAMP_NTZ | Original sign-up timestamp (assumed UTC). |
| `sign_up_at_mt` | TIMESTAMP_NTZ | Sign-up timestamp in Mountain Time. |
| `sign_up_date_mt` | DATE | Sign-up date in Mountain Time. |
| `sign_up_platform` | TEXT | Sign-up platform ('Unknown' if missing). |
| `country` | TEXT | Country as recorded in the source ('Unknown' if no geography). |
| `country_code` | TEXT | ISO-3166 alpha-2 country code ('Unknown' if no geography). |
| `country_currency_code` | TEXT | Local currency expected for the account's country. |
| `region` | TEXT | Region ('Unknown' if no geography). |
| `city` | TEXT | City ('Unknown' if no geography). |
| `has_geography` | BOOLEAN | FALSE when the account had no ACCOUNTS_GEO row. |

### `int_fx_rates_daily`

**Location:** `KAGGLE_DB.SILVER.INT_FX_RATES_DAILY`

Grain: one row per calendar date per currency across the reporting window. Each date takes the most recent rate published on or before it (ASOF JOIN), so weekends and holidays reuse the prior business day's rate and no future rate is ever applied. The only place FX as-of logic lives.

| Column | Type | Description |
|---|---|---|
| `rate_date` | DATE | Calendar date the rate applies to. |
| `from_currency` | TEXT | Original currency (ISO-4217). |
| `to_currency` | TEXT | Always USD. |
| `exchange_rate` | NUMBER | USD value of 1 unit of from_currency, effective on rate_date. |
| `rate_effective_date` | DATE | Publication date of the rate applied (on or before rate_date). |
| `days_since_published` | NUMBER | Days between rate_date and rate_effective_date. 0 on business days. |
| `source_series_id` | TEXT | FRED series identifier (NULL for USD). |
| `rate_source` | TEXT | Federal Reserve H.10 via FRED, or identity for USD. |
| `rate_type` | TEXT | Rate methodology. |
| `loaded_at` | TIMESTAMP_NTZ | Date the rates were retrieved. |

### `int_invoices`

**Location:** `KAGGLE_DB.SILVER.INT_INVOICES`

Grain: one row per invoice. Line items and payments are aggregated to invoice grain before joining (no fanout). Adds historical USD conversion at the invoice created date (MT), line item reconciliation, payment status and the account's lifecycle stage when the invoice was created.

| Column | Type | Description |
|---|---|---|
| `invoice_id` | TEXT | Invoice identifier. |
| `account_id` | TEXT | Account that issued the invoice. |
| `invoice_created_at_utc` | TIMESTAMP_NTZ | Original creation timestamp (assumed UTC). |
| `invoice_created_at_mt` | TIMESTAMP_NTZ | Creation timestamp in Mountain Time. |
| `invoice_created_date_mt` | DATE | Creation date in Mountain Time. FX conversion date. |
| `invoice_sent_at_utc` | TIMESTAMP_NTZ | Original sent timestamp (assumed UTC). |
| `invoice_sent_at_mt` | TIMESTAMP_NTZ | Sent timestamp in Mountain Time. |
| `invoice_sent_date_mt` | DATE | Sent date in Mountain Time. |
| `invoice_amount` | NUMBER | Invoice amount in the original currency. |
| `currency_code` | TEXT | Original invoice currency. |
| `exchange_rate` | NUMBER | USD per 1 unit of currency_code on invoice_created_date_mt. |
| `fx_rate_effective_date` | DATE | Publication date of the applied rate. |
| `fx_rate_source` | TEXT | Provider of the applied rate. |
| `invoice_amount_usd` | NUMBER | invoice_amount x exchange_rate. Unrounded. |
| `line_item_count` | NUMBER | Number of line items on the invoice. |
| `line_item_amount_total` | NUMBER | Sum of line item amounts (original currency). |
| `distinct_service_type_count` | NUMBER | Number of distinct service types on the invoice. |
| `is_amount_reconciled` | BOOLEAN | TRUE when invoice_amount equals line_item_amount_total. |
| `payment_count` | NUMBER | Number of payments recorded against the invoice. |
| `is_paid` | BOOLEAN | TRUE if at least one payment exists. |
| `lifecycle_stage_at_invoice` | TEXT | The account's lifecycle stage when the invoice was created (pre_trial if before any event). |
| `is_post_churn_activity` | BOOLEAN | TRUE if the invoice was created after the account churned. |

### `int_payment_transactions`

**Location:** `KAGGLE_DB.SILVER.INT_PAYMENT_TRANSACTIONS`

Grain: one row per payment transaction. Adds historical USD conversion at the transaction date (MT), payment channel classification and the account's lifecycle stage when the payment was made.

| Column | Type | Description |
|---|---|---|
| `transaction_id` | TEXT | Payment transaction identifier. |
| `account_id` | TEXT | Account that received the payment. |
| `invoice_id` | TEXT | Invoice the payment was made against. |
| `transaction_at_utc` | TIMESTAMP_NTZ | Original payment timestamp (assumed UTC). |
| `transaction_at_mt` | TIMESTAMP_NTZ | Payment timestamp in Mountain Time. |
| `transaction_date_mt` | DATE | Payment date in Mountain Time. FX conversion date. |
| `payment_method` | TEXT | Payment method as recorded in the source. |
| `payment_channel` | TEXT | electronic (Credit Card, ACH, Paypal) or offline (Cash, Cheque). |
| `payment_amount` | NUMBER | Payment amount in the original currency. |
| `currency_code` | TEXT | Original payment currency. |
| `exchange_rate` | NUMBER | USD per 1 unit of currency_code on transaction_date_mt. |
| `fx_rate_effective_date` | DATE | Publication date of the applied rate. |
| `fx_rate_source` | TEXT | Provider of the applied rate. |
| `amount_usd` | NUMBER | payment_amount x exchange_rate. Unrounded. |
| `lifecycle_stage_at_payment` | TEXT | The account's lifecycle stage when the payment was made (pre_trial if before any event). |
| `is_post_churn_activity` | BOOLEAN | TRUE if the payment occurred after the account churned. |

## Silver – Staging

### `stg_account_lifecycle_events`

**Location:** `KAGGLE_DB.SILVER.STG_ACCOUNT_LIFECYCLE_EVENTS`

Grain: one row per account lifecycle event. Adds a surrogate key derived from (account_id, event_time), because the source has no event identifier.

| Column | Type | Description |
|---|---|---|
| `lifecycle_event_id` | TEXT | Surrogate key = hash(account_id, event_time). |
| `account_id` | TEXT | Account the event belongs to. |
| `lifecycle_state` | TEXT | State the account entered (lowercased). |
| `event_at_utc` | TIMESTAMP_NTZ | Original event timestamp (assumed UTC). |
| `event_at_mt` | TIMESTAMP_NTZ | Event timestamp in Mountain Time. |
| `event_date_mt` | DATE | Event calendar date in Mountain Time. |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

### `stg_accounts`

**Location:** `KAGGLE_DB.SILVER.STG_ACCOUNTS`

Grain: one row per account. Standardised copy of BRONZE.ACCOUNTS. Renames id to account_id, keeps the original (assumed UTC) sign-up timestamp and adds its Mountain Time equivalent.

| Column | Type | Description |
|---|---|---|
| `account_id` | TEXT | Account identifier (renamed from source column id). |
| `sign_up_at_utc` | TIMESTAMP_NTZ | Original sign-up timestamp from the source (timezone-naive, assumed UTC). |
| `sign_up_at_mt` | TIMESTAMP_NTZ | Sign-up timestamp converted to Mountain Time (America/Denver). |
| `sign_up_date_mt` | DATE | Sign-up calendar date in Mountain Time. |
| `sign_up_platform` | TEXT | Platform the account signed up on (lowercased). |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

### `stg_accounts_geo`

**Location:** `KAGGLE_DB.SILVER.STG_ACCOUNTS_GEO`

Grain: one row per account. Standardised copy of BRONZE.ACCOUNTS_GEO with ISO country code and the account's expected local currency added from the country_reference seed. Source country names are kept unchanged.

| Column | Type | Description |
|---|---|---|
| `account_id` | TEXT | Account identifier. |
| `country` | TEXT | Country exactly as recorded in the source. |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. NULL here means the country is missing from country_reference. |
| `country_currency_code` | TEXT | Local currency expected for the account's country. |
| `region` | TEXT | Sales-territory-style region. Not strictly nested within city or vice versa (e.g. Leeds appears in England-Central and England-North). |
| `city` | TEXT | Account city. |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

### `stg_fx_rates`

**Location:** `KAGGLE_DB.SILVER.STG_FX_RATES`

Grain: one row per published rate date per currency. FRED H.10 series normalised to the convention "1 unit of from_currency = exchange_rate USD" (DEXCAUS is inverted; DEXUSUK and DEXUSAL are used as published), plus USD identity rows at 1.0. Only dates with a published rate appear here.

| Column | Type | Description |
|---|---|---|
| `rate_date` | DATE | Date the rate was published for. |
| `from_currency` | TEXT |  |
| `to_currency` | TEXT | Always USD. |
| `exchange_rate` | NUMBER | USD value of 1 unit of from_currency. |
| `source_series_id` | TEXT | FRED series the rate came from (NULL for USD identity rows). |
| `rate_source` | TEXT | Provider of the rate. |
| `rate_type` | TEXT | Rate methodology (daily noon buying rate, or identity). |
| `loaded_at` | TIMESTAMP_NTZ | Date the source series was retrieved from FRED. |

### `stg_invoice_line_items`

**Location:** `KAGGLE_DB.SILVER.STG_INVOICE_LINE_ITEMS`

Grain - one row per invoice line item. Line items inherit their invoice's currency.

| Column | Type | Description |
|---|---|---|
| `invoice_line_item_id` | TEXT | Line item identifier (renamed from source column id). |
| `invoice_id` | TEXT | Parent invoice. |
| `service_type` | TEXT | Type of service billed (lowercased). |
| `line_item_amount` | NUMBER | Line item amount in the parent invoice's currency (major units). |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

### `stg_invoices`

**Location:** `KAGGLE_DB.SILVER.STG_INVOICES`

Grain: one row per invoice. Original amount and currency preserved; timestamps provided in both source (UTC) and Mountain Time.

| Column | Type | Description |
|---|---|---|
| `invoice_id` | TEXT | Invoice identifier. |
| `account_id` | TEXT | Account that issued the invoice. |
| `invoice_created_at_utc` | TIMESTAMP_NTZ | Original invoice creation timestamp (assumed UTC). |
| `invoice_created_at_mt` | TIMESTAMP_NTZ | Invoice creation timestamp in Mountain Time. |
| `invoice_created_date_mt` | DATE | Invoice creation date in Mountain Time. |
| `invoice_sent_at_utc` | TIMESTAMP_NTZ | Original invoice sent timestamp (assumed UTC). |
| `invoice_sent_at_mt` | TIMESTAMP_NTZ | Invoice sent timestamp in Mountain Time. |
| `invoice_sent_date_mt` | DATE | Invoice sent date in Mountain Time. |
| `invoice_amount` | NUMBER | Invoice amount in the original currency (major units). |
| `currency_code` | TEXT | ISO-4217 currency of the invoice. |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

### `stg_payment_transactions`

**Location:** `KAGGLE_DB.SILVER.STG_PAYMENT_TRANSACTIONS`

Grain: one row per payment transaction. The source has no status, refund or reversal fields, so every transaction is treated as a completed payment.

| Column | Type | Description |
|---|---|---|
| `transaction_id` | TEXT | Payment transaction identifier. |
| `invoice_id` | TEXT | Invoice the payment was made against. |
| `account_id` | TEXT | Account that received the payment. |
| `transaction_at_utc` | TIMESTAMP_NTZ | Original payment timestamp (assumed UTC). |
| `transaction_at_mt` | TIMESTAMP_NTZ | Payment timestamp in Mountain Time. |
| `transaction_date_mt` | DATE | Payment date in Mountain Time. |
| `payment_method` | TEXT | Payment method as recorded in the source. |
| `payment_amount` | NUMBER | Payment amount in the original currency (major units). |
| `currency_code` | TEXT | ISO-4217 currency of the payment. |
| `source_file` | TEXT | Staged CSV file the row was loaded from. |
| `loaded_at` | TIMESTAMP_LTZ | Timestamp the row was loaded into Bronze. |

## Seeds

### `country_reference`

**Location:** `KAGGLE_DB.SILVER.COUNTRY_REFERENCE`

Static mapping of source country names to ISO-3166 alpha-2 codes and the local currency expected for accounts in that country.

| Column | Type | Description |
|---|---|---|
| `source_country_name` | TEXT | Country name exactly as it appears in ACCOUNTS_GEO. |
| `country_code` | TEXT | ISO-3166 alpha-2 country code. |
| `currency_code` | TEXT | ISO-4217 local currency code for the country. |

### `fx_rates_fred_h10`

**Location:** `KAGGLE_DB.SILVER.FX_RATES_FRED_H10`

Daily foreign exchange rates from the Federal Reserve H.10 release (noon buying rates in New York), downloaded from FRED (St. Louis Fed) on retrieved_date. Public domain. Values are stored exactly as published; US holidays with no published value are omitted (never imputed). Series: DEXCAUS = CAD per 1 USD, DEXUSUK = USD per 1 GBP, DEXUSAL = USD per 1 AUD. Normalisation to "1 unit of currency = X USD" happens in stg_fx_rates.

| Column | Type | Description |
|---|---|---|
| `rate_date` | DATE | Business date the rate was published for. |
| `series_id` | TEXT | FRED series identifier. |
| `observed_value` | NUMBER | Rate exactly as published, in the series' own quote convention. |
| `retrieved_date` | DATE | Date the series was downloaded from FRED. |
