-- Grain: one row per reporting date (MT) x country x region x city x sign-up platform,
-- for combinations with any payment or invoice activity (sparse).
-- GPV is dated by transaction date; invoice metrics by invoice created date.
-- All measures are fully additive across every dimension and date.

WITH accounts AS (

    SELECT
        account_id
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM {{ ref('dim_accounts') }}

)

-- Payments and invoices are aggregated independently to the mart grain
-- before combining, so neither fact can inflate the other.
,payments_daily AS (

    SELECT
        payments.transaction_date_mt AS reporting_date
        ,COALESCE(accounts.country, 'Unknown') AS country
        ,COALESCE(accounts.country_code, 'Unknown') AS country_code
        ,COALESCE(accounts.region, 'Unknown') AS region
        ,COALESCE(accounts.city, 'Unknown') AS city
        ,COALESCE(accounts.sign_up_platform, 'Unknown') AS sign_up_platform
        ,SUM(payments.amount_usd) AS gpv_usd
        ,SUM(IFF(payments.payment_channel = 'electronic', payments.amount_usd, 0)) AS gpv_electronic_usd
        ,SUM(IFF(payments.payment_channel = 'offline', payments.amount_usd, 0)) AS gpv_offline_usd
        ,COUNT(payments.transaction_id) AS payment_count
    FROM {{ ref('fct_payment_transactions') }} AS payments
    LEFT JOIN accounts
        ON payments.account_id = accounts.account_id
    GROUP BY
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform

)

,invoices_daily AS (

    SELECT
        invoices.invoice_created_date_mt AS reporting_date
        ,COALESCE(accounts.country, 'Unknown') AS country
        ,COALESCE(accounts.country_code, 'Unknown') AS country_code
        ,COALESCE(accounts.region, 'Unknown') AS region
        ,COALESCE(accounts.city, 'Unknown') AS city
        ,COALESCE(accounts.sign_up_platform, 'Unknown') AS sign_up_platform
        ,COUNT(DISTINCT invoices.invoice_id) AS invoice_count
        ,SUM(invoices.invoice_amount_usd) AS invoice_amount_usd
    FROM {{ ref('fct_invoices') }} AS invoices
    LEFT JOIN accounts
        ON invoices.account_id = accounts.account_id
    GROUP BY
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform

)

-- Every grain combination present in either source.
,grain_keys AS (

    SELECT
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM payments_daily

    UNION

    SELECT
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM invoices_daily

)

,final AS (

    SELECT
        grain_keys.reporting_date
        ,grain_keys.country
        ,grain_keys.country_code
        ,grain_keys.region
        ,grain_keys.city
        ,grain_keys.sign_up_platform
        ,COALESCE(payments_daily.gpv_usd, 0) AS gpv_usd
        ,COALESCE(payments_daily.gpv_electronic_usd, 0) AS gpv_electronic_usd
        ,COALESCE(payments_daily.gpv_offline_usd, 0) AS gpv_offline_usd
        ,COALESCE(payments_daily.payment_count, 0) AS payment_count
        ,COALESCE(invoices_daily.invoice_count, 0) AS invoice_count
        ,COALESCE(invoices_daily.invoice_amount_usd, 0) AS invoice_amount_usd
    FROM grain_keys
    LEFT JOIN payments_daily
        USING (reporting_date, country, country_code, region, city, sign_up_platform)
    LEFT JOIN invoices_daily
        USING (reporting_date, country, country_code, region, city, sign_up_platform)

)

SELECT *
FROM final
