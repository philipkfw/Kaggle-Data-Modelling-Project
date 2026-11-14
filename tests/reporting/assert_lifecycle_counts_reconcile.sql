-- Lifecycle stage counts must reconcile with lifecycle history:
--   1. Daily mart stocks = account-day snapshot counts, for every date.
--   2. Daily total_accounts = accounts signed up on or before that date.
--   3. Stocks on the reporting end date = current stages in dim_accounts.
--   4. Daily mart flows = lifecycle events in fct_account_lifecycle.

WITH snapshot_by_date AS (

    SELECT
        status_date AS reporting_date
        ,SUM(is_pre_trial) AS pre_trial_accounts
        ,SUM(is_trial) AS trial_accounts
        ,SUM(is_subscribed) AS subscribed_accounts
        ,SUM(is_churned) AS churned_accounts
        ,COUNT(account_id) AS total_accounts
    FROM {{ ref('fct_account_daily_status') }}
    GROUP BY status_date

)

,mart_by_date AS (

    SELECT
        reporting_date
        ,SUM(pre_trial_accounts) AS pre_trial_accounts
        ,SUM(trial_accounts) AS trial_accounts
        ,SUM(subscribed_accounts) AS subscribed_accounts
        ,SUM(churned_accounts) AS churned_accounts
        ,SUM(total_accounts) AS total_accounts
    FROM {{ ref('mart_account_lifecycle') }}
    GROUP BY reporting_date

)

,signed_up_by_date AS (

    SELECT
        calendar.date_day AS reporting_date
        ,COUNT(accounts.account_id) AS total_accounts
    FROM {{ ref('dim_date') }} AS calendar
    INNER JOIN {{ ref('dim_accounts') }} AS accounts
        ON accounts.sign_up_date_mt <= calendar.date_day
    GROUP BY calendar.date_day

)

,current_stages AS (

    SELECT
        COUNT_IF(current_lifecycle_stage = 'pre_trial') AS pre_trial_accounts
        ,COUNT_IF(current_lifecycle_stage = 'trial') AS trial_accounts
        ,COUNT_IF(current_lifecycle_stage = 'subscribed') AS subscribed_accounts
        ,COUNT_IF(current_lifecycle_stage = 'churned') AS churned_accounts
    FROM {{ ref('dim_accounts') }}

)

,event_totals AS (

    SELECT
        COUNT_IF(lifecycle_state = 'trial') AS new_trials
        ,COUNT_IF(lifecycle_state = 'subscribed') AS new_subscriptions
        ,COUNT_IF(lifecycle_state = 'churned') AS new_churns
    FROM {{ ref('fct_account_lifecycle') }}

)

,mart_flow_totals AS (

    SELECT
        SUM(new_trials) AS new_trials
        ,SUM(new_subscriptions) AS new_subscriptions
        ,SUM(new_churns) AS new_churns
    FROM {{ ref('mart_account_lifecycle') }}

)

SELECT
    'mart_vs_snapshot_' || TO_CHAR(snapshot_by_date.reporting_date) AS check_name
FROM snapshot_by_date
FULL OUTER JOIN mart_by_date
    ON snapshot_by_date.reporting_date = mart_by_date.reporting_date
WHERE snapshot_by_date.pre_trial_accounts IS DISTINCT FROM mart_by_date.pre_trial_accounts
    OR snapshot_by_date.trial_accounts IS DISTINCT FROM mart_by_date.trial_accounts
    OR snapshot_by_date.subscribed_accounts IS DISTINCT FROM mart_by_date.subscribed_accounts
    OR snapshot_by_date.churned_accounts IS DISTINCT FROM mart_by_date.churned_accounts
    OR snapshot_by_date.total_accounts IS DISTINCT FROM mart_by_date.total_accounts

UNION ALL

SELECT
    'total_vs_signed_up_' || TO_CHAR(signed_up_by_date.reporting_date) AS check_name
FROM signed_up_by_date
LEFT JOIN mart_by_date
    ON signed_up_by_date.reporting_date = mart_by_date.reporting_date
WHERE signed_up_by_date.total_accounts IS DISTINCT FROM mart_by_date.total_accounts

UNION ALL

SELECT
    'reporting_end_vs_current_stage' AS check_name
FROM mart_by_date
CROSS JOIN current_stages
WHERE mart_by_date.reporting_date = CAST('{{ var("reporting_end_date") }}' AS DATE)
    AND (
        mart_by_date.pre_trial_accounts <> current_stages.pre_trial_accounts
        OR mart_by_date.trial_accounts <> current_stages.trial_accounts
        OR mart_by_date.subscribed_accounts <> current_stages.subscribed_accounts
        OR mart_by_date.churned_accounts <> current_stages.churned_accounts
    )

UNION ALL

SELECT
    'flows_vs_events' AS check_name
FROM event_totals
CROSS JOIN mart_flow_totals
WHERE event_totals.new_trials <> mart_flow_totals.new_trials
    OR event_totals.new_subscriptions <> mart_flow_totals.new_subscriptions
    OR event_totals.new_churns <> mart_flow_totals.new_churns
