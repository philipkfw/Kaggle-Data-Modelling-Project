-- The monthly mart must agree with the daily marts it is built from:
-- month-end stocks equal the daily stocks on the month's last reporting date,
-- and monthly flows equal the sum of daily flows.

WITH monthly AS (

    SELECT
        month_start_date
        ,month_reporting_end_date
        ,SUM(subscribed_accounts_eom) AS subscribed_accounts_eom
        ,SUM(total_accounts_eom) AS total_accounts_eom
        ,SUM(new_subscriptions) AS new_subscriptions
        ,SUM(new_churns) AS new_churns
    FROM {{ ref('mart_account_performance') }}
    GROUP BY
        month_start_date
        ,month_reporting_end_date

)

,daily_month_end AS (

    SELECT
        reporting_date
        ,SUM(subscribed_accounts) AS subscribed_accounts
        ,SUM(total_accounts) AS total_accounts
    FROM {{ ref('mart_account_lifecycle') }}
    GROUP BY reporting_date

)

,daily_flows AS (

    SELECT
        DATE_TRUNC('MONTH', reporting_date) AS month_start_date
        ,SUM(new_subscriptions) AS new_subscriptions
        ,SUM(new_churns) AS new_churns
    FROM {{ ref('mart_account_lifecycle') }}
    GROUP BY month_start_date

)

SELECT
    monthly.month_start_date
    ,monthly.subscribed_accounts_eom
    ,daily_month_end.subscribed_accounts
    ,monthly.total_accounts_eom
    ,daily_month_end.total_accounts
    ,monthly.new_subscriptions
    ,daily_flows.new_subscriptions AS daily_new_subscriptions
    ,monthly.new_churns
    ,daily_flows.new_churns AS daily_new_churns
FROM monthly
LEFT JOIN daily_month_end
    ON monthly.month_reporting_end_date = daily_month_end.reporting_date
LEFT JOIN daily_flows
    ON monthly.month_start_date = daily_flows.month_start_date
WHERE monthly.subscribed_accounts_eom IS DISTINCT FROM daily_month_end.subscribed_accounts
    OR monthly.total_accounts_eom IS DISTINCT FROM daily_month_end.total_accounts
    OR monthly.new_subscriptions IS DISTINCT FROM daily_flows.new_subscriptions
    OR monthly.new_churns IS DISTINCT FROM daily_flows.new_churns
