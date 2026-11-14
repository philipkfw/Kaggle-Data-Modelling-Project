-- GPV must reconcile at every layer:
--   1. Bronze source vs fact: same transaction count and original amount per currency.
--   2. Fact vs marts: same USD total in the daily and monthly marts.
--   3. Electronic + offline GPV must equal total GPV.

WITH source_totals AS (

    SELECT
        UPPER(TRIM(currency)) AS currency_code
        ,COUNT(transaction_id) AS transaction_count
        ,SUM(amount) AS amount
    FROM {{ source('bronze', 'payment_transactions') }}
    GROUP BY currency_code

)

,fact_totals AS (

    SELECT
        currency_code
        ,COUNT(transaction_id) AS transaction_count
        ,SUM(payment_amount) AS amount
    FROM {{ ref('fct_payment_transactions') }}
    GROUP BY currency_code

)

,source_vs_fact AS (

    SELECT
        'source_vs_fact_' || COALESCE(source_totals.currency_code, fact_totals.currency_code) AS check_name
        ,source_totals.amount AS expected_value
        ,fact_totals.amount AS actual_value
    FROM source_totals
    FULL OUTER JOIN fact_totals
        ON source_totals.currency_code = fact_totals.currency_code
    WHERE source_totals.transaction_count IS DISTINCT FROM fact_totals.transaction_count
        OR source_totals.amount IS DISTINCT FROM fact_totals.amount

)

,usd_totals AS (

    SELECT
        (SELECT SUM(amount_usd) FROM {{ ref('fct_payment_transactions') }}) AS fact_gpv_usd
        ,(SELECT SUM(gpv_usd) FROM {{ ref('mart_financial_performance') }}) AS daily_mart_gpv_usd
        ,(SELECT SUM(gpv_electronic_usd) + SUM(gpv_offline_usd) FROM {{ ref('mart_financial_performance') }}) AS daily_mart_channel_gpv_usd
        ,(SELECT SUM(gpv_usd) FROM {{ ref('mart_account_performance') }}) AS monthly_mart_gpv_usd

)

,usd_checks AS (

    SELECT
        'fact_vs_daily_mart' AS check_name
        ,fact_gpv_usd AS expected_value
        ,daily_mart_gpv_usd AS actual_value
    FROM usd_totals
    WHERE ABS(fact_gpv_usd - daily_mart_gpv_usd) > 0.01

    UNION ALL

    SELECT
        'channel_split_vs_total' AS check_name
        ,daily_mart_gpv_usd AS expected_value
        ,daily_mart_channel_gpv_usd AS actual_value
    FROM usd_totals
    WHERE ABS(daily_mart_gpv_usd - daily_mart_channel_gpv_usd) > 0.01

    UNION ALL

    SELECT
        'fact_vs_monthly_mart' AS check_name
        ,fact_gpv_usd AS expected_value
        ,monthly_mart_gpv_usd AS actual_value
    FROM usd_totals
    WHERE ABS(fact_gpv_usd - monthly_mart_gpv_usd) > 0.01

)

SELECT * FROM source_vs_fact
UNION ALL
SELECT * FROM usd_checks
