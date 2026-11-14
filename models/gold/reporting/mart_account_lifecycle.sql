-- Grain: one row per reporting date (MT) x country x region x city x sign-up platform,
-- for every date from the segment's first sign-up onward (dense).
--
-- Two kinds of measure - never mix them:
--   STOCKS (*_accounts): point-in-time count of accounts in each stage at end of day.
--     Semi-additive: sum across segments, but NEVER across dates (use the period's last date).
--   FLOWS (new_*): count of events that happened on the date. Fully additive.

WITH accounts AS (

    SELECT
        account_id
        ,sign_up_date_mt
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM {{ ref('dim_accounts') }}

)

,stocks_daily AS (

    SELECT
        daily_status.status_date AS reporting_date
        ,COALESCE(accounts.country, 'Unknown') AS country
        ,COALESCE(accounts.country_code, 'Unknown') AS country_code
        ,COALESCE(accounts.region, 'Unknown') AS region
        ,COALESCE(accounts.city, 'Unknown') AS city
        ,COALESCE(accounts.sign_up_platform, 'Unknown') AS sign_up_platform
        ,SUM(daily_status.is_pre_trial) AS pre_trial_accounts
        ,SUM(daily_status.is_trial) AS trial_accounts
        ,SUM(daily_status.is_subscribed) AS subscribed_accounts
        ,SUM(daily_status.is_churned) AS churned_accounts
        ,COUNT(daily_status.account_id) AS total_accounts
    FROM {{ ref('fct_account_daily_status') }} AS daily_status
    LEFT JOIN accounts
        ON daily_status.account_id = accounts.account_id
    GROUP BY
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform

)

,lifecycle_flows_daily AS (

    SELECT
        lifecycle.event_date_mt AS reporting_date
        ,COALESCE(accounts.country, 'Unknown') AS country
        ,COALESCE(accounts.country_code, 'Unknown') AS country_code
        ,COALESCE(accounts.region, 'Unknown') AS region
        ,COALESCE(accounts.city, 'Unknown') AS city
        ,COALESCE(accounts.sign_up_platform, 'Unknown') AS sign_up_platform
        ,COUNT_IF(lifecycle.lifecycle_state = 'trial') AS new_trials
        ,COUNT_IF(lifecycle.lifecycle_state = 'subscribed') AS new_subscriptions
        ,COUNT_IF(lifecycle.lifecycle_state = 'churned') AS new_churns
    FROM {{ ref('fct_account_lifecycle') }} AS lifecycle
    LEFT JOIN accounts
        ON lifecycle.account_id = accounts.account_id
    GROUP BY
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform

)

,sign_ups_daily AS (

    SELECT
        sign_up_date_mt AS reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
        ,COUNT(account_id) AS new_sign_ups
    FROM accounts
    GROUP BY
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform

)

,grain_keys AS (

    SELECT
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM stocks_daily

    UNION

    SELECT
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM lifecycle_flows_daily

    UNION

    SELECT
        reporting_date
        ,country
        ,country_code
        ,region
        ,city
        ,sign_up_platform
    FROM sign_ups_daily

)

,final AS (

    SELECT
        grain_keys.reporting_date
        ,grain_keys.country
        ,grain_keys.country_code
        ,grain_keys.region
        ,grain_keys.city
        ,grain_keys.sign_up_platform
        ,COALESCE(stocks_daily.pre_trial_accounts, 0) AS pre_trial_accounts
        ,COALESCE(stocks_daily.trial_accounts, 0) AS trial_accounts
        ,COALESCE(stocks_daily.subscribed_accounts, 0) AS subscribed_accounts
        ,COALESCE(stocks_daily.churned_accounts, 0) AS churned_accounts
        ,COALESCE(stocks_daily.total_accounts, 0) AS total_accounts
        ,COALESCE(sign_ups_daily.new_sign_ups, 0) AS new_sign_ups
        ,COALESCE(lifecycle_flows_daily.new_trials, 0) AS new_trials
        ,COALESCE(lifecycle_flows_daily.new_subscriptions, 0) AS new_subscriptions
        ,COALESCE(lifecycle_flows_daily.new_churns, 0) AS new_churns
    FROM grain_keys
    LEFT JOIN stocks_daily
        USING (reporting_date, country, country_code, region, city, sign_up_platform)
    LEFT JOIN lifecycle_flows_daily
        USING (reporting_date, country, country_code, region, city, sign_up_platform)
    LEFT JOIN sign_ups_daily
        USING (reporting_date, country, country_code, region, city, sign_up_platform)

)

SELECT *
FROM final
