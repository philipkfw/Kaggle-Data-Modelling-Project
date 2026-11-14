-- Grain: one row per account lifecycle event = one effective-dated interval.
-- Authoritative source for lifecycle flows (new trials, subscriptions, churns)
-- and for reconstructing an account's state at any point in time.

WITH lifecycle AS (

    SELECT *
    FROM {{ ref('int_account_lifecycle') }}

)

,final AS (

    SELECT
        lifecycle_event_id
        ,account_id
        ,event_sequence
        ,lifecycle_state
        ,previous_lifecycle_state
        ,next_lifecycle_state
        ,event_at_mt
        ,event_date_mt
        ,valid_from_mt
        ,valid_to_mt
        ,is_current
        ,is_valid_transition
        ,days_in_state
    FROM lifecycle

)

SELECT *
FROM final
