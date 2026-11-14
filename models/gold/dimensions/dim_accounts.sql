-- Grain: one row per account, with CURRENT attributes (as of the reporting end date).
-- Used for geographic and sign-up platform segmentation, and for account-level
-- trial conversion analysis via the lifecycle milestone columns.
-- Historical lifecycle state lives in fct_account_lifecycle / fct_account_daily_status.

WITH accounts AS (

    SELECT *
    FROM {{ ref('int_accounts_enriched') }}

)

,lifecycle AS (

    SELECT *
    FROM {{ ref('int_account_lifecycle') }}

)

,lifecycle_milestones AS (

    SELECT
        account_id
        ,MIN(IFF(lifecycle_state = 'trial', event_at_mt, NULL)) AS trial_started_at_mt
        ,MIN(IFF(lifecycle_state = 'subscribed', event_at_mt, NULL)) AS subscribed_at_mt
        ,MIN(IFF(lifecycle_state = 'churned', event_at_mt, NULL)) AS churned_at_mt
        ,MAX(IFF(is_current, lifecycle_state, NULL)) AS current_lifecycle_state
        ,MAX(IFF(is_current, event_at_mt, NULL)) AS current_stage_started_at_mt
        ,COUNT(lifecycle_event_id) AS lifecycle_event_count
    FROM lifecycle
    GROUP BY account_id

)

,final AS (

    SELECT
        accounts.account_id
        ,accounts.sign_up_at_mt
        ,accounts.sign_up_date_mt
        ,accounts.sign_up_platform
        ,accounts.country
        ,accounts.country_code
        ,accounts.region
        ,accounts.city
        ,accounts.has_geography
        -- Accounts with no lifecycle event yet are in the derived pre_trial stage.
        ,COALESCE(lifecycle_milestones.current_lifecycle_state, 'pre_trial') AS current_lifecycle_stage
        ,COALESCE(lifecycle_milestones.current_stage_started_at_mt, accounts.sign_up_at_mt) AS current_stage_started_at_mt
        ,lifecycle_milestones.trial_started_at_mt
        ,TO_DATE(lifecycle_milestones.trial_started_at_mt) AS trial_started_date_mt
        ,lifecycle_milestones.subscribed_at_mt
        ,TO_DATE(lifecycle_milestones.subscribed_at_mt) AS subscribed_date_mt
        ,lifecycle_milestones.churned_at_mt
        ,TO_DATE(lifecycle_milestones.churned_at_mt) AS churned_date_mt
        ,DATEDIFF(DAY, accounts.sign_up_at_mt, lifecycle_milestones.trial_started_at_mt) AS days_sign_up_to_trial
        ,DATEDIFF(DAY, lifecycle_milestones.trial_started_at_mt, lifecycle_milestones.subscribed_at_mt) AS days_trial_to_subscribed
        ,DATEDIFF(DAY, lifecycle_milestones.subscribed_at_mt, lifecycle_milestones.churned_at_mt) AS days_subscribed_to_churned
        ,lifecycle_milestones.subscribed_at_mt IS NOT NULL AS has_converted
        ,COALESCE(
            DATEDIFF(DAY, lifecycle_milestones.trial_started_at_mt, lifecycle_milestones.subscribed_at_mt)
                <= {{ var('trial_conversion_window_days') }}
            ,FALSE
        ) AS has_converted_within_window
        -- Data quality flag: still recorded as trial long after any trial has ever converted.
        ,COALESCE(lifecycle_milestones.current_lifecycle_state, 'pre_trial') = 'trial'
            AND DATEDIFF(
                DAY
                ,lifecycle_milestones.trial_started_at_mt
                ,CAST('{{ var("reporting_end_date") }}' AS DATE)
            ) > {{ var('stale_trial_days') }} AS is_stale_trial
        ,COALESCE(lifecycle_milestones.lifecycle_event_count, 0) AS lifecycle_event_count
    FROM accounts
    LEFT JOIN lifecycle_milestones
        ON accounts.account_id = lifecycle_milestones.account_id

)

SELECT *
FROM final
