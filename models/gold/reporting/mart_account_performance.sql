-- Grain: one row per month x country x region x city x sign-up platform.
-- Executive view combining financial and lifecycle metrics. Each input is rolled
-- up to this grain independently, then joined on identical keys (no fact-to-fact joins).
--
--   Stocks (*_eom): as of the month's last reporting date. Do not sum across months.
--   Flows and financials: totals within the month. Fully additive.

WITH calendar AS (

    SELECT
        date_day
        ,month_start_date
        ,month_reporting_end_date
    FROM {{ ref('dim_date') }}

)

,lifecycle_daily AS (

    SELECT *
    FROM {{ ref('mart_account_lifecycle') }}

)

,lifecycle_month_end AS (

    SELECT
        calendar.month_start_date
        ,lifecycle_daily.country
        ,lifecycle_daily.country_code
        ,lifecycle_daily.region
        ,lifecycle_daily.city
        ,lifecycle_daily.sign_up_platform
        ,lifecycle_daily.pre_trial_accounts AS pre_trial_accounts_eom
        ,lifecycle_daily.trial_accounts AS trial_accounts_eom
        ,lifecycle_daily.subscribed_accounts AS subscribed_accounts_eom
        ,lifecycle_daily.churned_accounts AS churned_accounts_eom
        ,lifecycle_daily.total_accounts AS total_accounts_eom
    FROM lifecycle_daily
    INNER JOIN calendar
        ON lifecycle_daily.reporting_date = calendar.date_day
    WHERE lifecycle_daily.reporting_date = calendar.month_reporting_end_date

)

,lifecycle_flows_monthly AS (

    SELECT
        calendar.month_start_date
        ,lifecycle_daily.country
        ,lifecycle_daily.country_code
        ,lifecycle_daily.region
        ,lifecycle_daily.city
        ,lifecycle_daily.sign_up_platform
        ,SUM(lifecycle_daily.new_sign_ups) AS new_sign_ups
        ,SUM(lifecycle_daily.new_trials) AS new_trials
        ,SUM(lifecycle_daily.new_subscriptions) AS new_subscriptions
        ,SUM(lifecycle_daily.new_churns) AS new_churns
    FROM lifecycle_daily
    INNER JOIN calendar
        ON lifecycle_daily.reporting_date = calendar.date_day
    GROUP BY
        calendar.month_start_date
        ,lifecycle_daily.country
        ,lifecycle_daily.country_code
        ,lifecycle_daily.region
        ,lifecycle_daily.city
        ,lifecycle_daily.sign_up_platform

)

,financial_monthly AS (

    SELECT
        calendar.month_start_date
        ,financial.country
        ,financial.country_code
        ,financial.region
        ,financial.city
        ,financial.sign_up_platform
        ,SUM(financial.gpv_usd) AS gpv_usd
        ,SUM(financial.gpv_electronic_usd) AS gpv_electronic_usd
        ,SUM(financial.gpv_offline_usd) AS gpv_offline_usd
        ,SUM(financial.payment_count) AS payment_count
        ,SUM(financial.invoice_count) AS invoice_count
        ,SUM(financial.invoice_amount_usd) AS invoice_amount_usd
    FROM {{ ref('mart_financial_performance') }} AS financial
    INNER JOIN calendar
        ON financial.reporting_date = calendar.date_day
    GROUP BY
        calendar.month_start_date
        ,financial.country
        ,financial.country_code
        ,financial.region
        ,financial.city
        ,financial.sign_up_platform

)

-- Every month x segment present in any input, so no input's rows are dropped.
,grain_keys AS (

    SELECT
        month_start_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM lifecycle_month_end

    UNION

    SELECT
        month_start_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM lifecycle_flows_monthly

    UNION

    SELECT
        month_start_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM financial_monthly

)

,final AS (

    SELECT
        grain_keys.month_start_date
        ,LEAST(
            LAST_DAY(grain_keys.month_start_date, 'MONTH')
            ,CAST('{{ var("reporting_end_date") }}' AS DATE)
        ) AS month_reporting_end_date
        ,LAST_DAY(grain_keys.month_start_date, 'MONTH') > CAST('{{ var("reporting_end_date") }}' AS DATE) AS is_partial_month
        ,grain_keys.country
        ,grain_keys.country_code
        ,grain_keys.region
        ,grain_keys.city
        ,grain_keys.sign_up_platform
        -- Lifecycle stocks (end of month)
        ,COALESCE(lifecycle.pre_trial_accounts_eom, 0) AS pre_trial_accounts_eom
        ,COALESCE(lifecycle.trial_accounts_eom, 0) AS trial_accounts_eom
        ,COALESCE(lifecycle.subscribed_accounts_eom, 0) AS subscribed_accounts_eom
        ,COALESCE(lifecycle.churned_accounts_eom, 0) AS churned_accounts_eom
        ,COALESCE(lifecycle.total_accounts_eom, 0) AS total_accounts_eom
        -- Lifecycle flows (within month)
        ,COALESCE(flows.new_sign_ups, 0) AS new_sign_ups
        ,COALESCE(flows.new_trials, 0) AS new_trials
        ,COALESCE(flows.new_subscriptions, 0) AS new_subscriptions
        ,COALESCE(flows.new_churns, 0) AS new_churns
        -- Financials (within month)
        ,COALESCE(financial.gpv_usd, 0) AS gpv_usd
        ,COALESCE(financial.gpv_electronic_usd, 0) AS gpv_electronic_usd
        ,COALESCE(financial.gpv_offline_usd, 0) AS gpv_offline_usd
        ,COALESCE(financial.payment_count, 0) AS payment_count
        ,COALESCE(financial.invoice_count, 0) AS invoice_count
        ,COALESCE(financial.invoice_amount_usd, 0) AS invoice_amount_usd
    FROM grain_keys
    LEFT JOIN lifecycle_month_end AS lifecycle
        USING (month_start_date, country, country_code, region, city, sign_up_platform)
    LEFT JOIN lifecycle_flows_monthly AS flows
        USING (month_start_date, country, country_code, region, city, sign_up_platform)
    LEFT JOIN financial_monthly AS financial
        USING (month_start_date, country, country_code, region, city, sign_up_platform)

)

SELECT *
FROM final
