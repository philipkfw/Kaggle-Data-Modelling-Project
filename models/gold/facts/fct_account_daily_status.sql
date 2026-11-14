-- Grain: one row per account per calendar date (MT), from the account's sign-up
-- date to the reporting end date.
-- Stores each account's lifecycle stage at END OF DAY (Mountain Time), so
-- point-in-time counts become simple filters and sums.
-- Each account has exactly one stage per day, so stages can't double-count.

WITH calendar AS (

    SELECT
        date_day
    FROM {{ ref('dim_date') }}

)

,accounts AS (

    SELECT
        account_id
        ,sign_up_date_mt
    FROM {{ ref('int_accounts_enriched') }}

)

,lifecycle AS (

    SELECT *
    FROM {{ ref('int_account_lifecycle') }}

)

,account_days AS (

    SELECT
        accounts.account_id
        ,calendar.date_day
        -- Exclusive end-of-day boundary in Mountain Time.
        ,DATEADD(DAY, 1, CAST(calendar.date_day AS TIMESTAMP_NTZ)) AS next_day_start_mt
    FROM accounts
    INNER JOIN calendar
        ON calendar.date_day >= accounts.sign_up_date_mt

)

-- Latest lifecycle event strictly before the next day starts = end-of-day state.
,end_of_day_status AS (

    SELECT
        account_days.account_id
        ,account_days.date_day
        ,lifecycle.lifecycle_event_id
        ,lifecycle.lifecycle_state
    FROM account_days
    ASOF JOIN lifecycle
        MATCH_CONDITION (account_days.next_day_start_mt > lifecycle.event_at_mt)
        ON account_days.account_id = lifecycle.account_id

)

,final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['account_id', 'date_day']) }} AS account_daily_status_id
        ,date_day AS status_date
        ,account_id
        ,COALESCE(lifecycle_state, 'pre_trial') AS lifecycle_stage
        ,lifecycle_event_id
        ,IFF(COALESCE(lifecycle_state, 'pre_trial') = 'pre_trial', 1, 0) AS is_pre_trial
        ,IFF(lifecycle_state = 'trial', 1, 0) AS is_trial
        ,IFF(lifecycle_state = 'subscribed', 1, 0) AS is_subscribed
        ,IFF(lifecycle_state = 'churned', 1, 0) AS is_churned
    FROM end_of_day_status

)

SELECT *
FROM final
