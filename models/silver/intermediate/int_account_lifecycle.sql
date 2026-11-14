-- Grain: one row per account lifecycle event. Each event opens an effective-dated
-- interval [valid_from, valid_to) that closes when the account's next event occurs.
-- History is never overwritten: the current state is simply the open interval.

WITH events AS (

    SELECT *
    FROM {{ ref('stg_account_lifecycle_events') }}

)

,ranked AS (

    SELECT
        events.*
        -- Deterministic tie-break if two events ever share a timestamp
        -- (none do today): order by the natural lifecycle progression.
        ,CASE lifecycle_state
            WHEN 'trial' THEN 1
            WHEN 'subscribed' THEN 2
            WHEN 'churned' THEN 3
            ELSE 99
        END AS lifecycle_state_rank
    FROM events

)

,sequenced AS (

    SELECT
        ranked.*
        ,ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY event_at_utc, lifecycle_state_rank
        ) AS event_sequence
    FROM ranked

)

,with_neighbours AS (

    SELECT
        sequenced.*
        ,LAG(lifecycle_state) OVER (
            PARTITION BY account_id
            ORDER BY event_sequence
        ) AS previous_lifecycle_state
        ,LEAD(lifecycle_state) OVER (
            PARTITION BY account_id
            ORDER BY event_sequence
        ) AS next_lifecycle_state
        ,LEAD(event_at_utc) OVER (
            PARTITION BY account_id
            ORDER BY event_sequence
        ) AS next_event_at_utc
        ,LEAD(event_at_mt) OVER (
            PARTITION BY account_id
            ORDER BY event_sequence
        ) AS next_event_at_mt
    FROM sequenced

)

,final AS (

    SELECT
        lifecycle_event_id
        ,account_id
        ,event_sequence
        ,lifecycle_state
        ,previous_lifecycle_state
        ,next_lifecycle_state
        ,event_at_utc
        ,event_at_mt
        ,event_date_mt
        -- Intervals are compared in UTC downstream: Mountain Time repeats an hour
        -- when daylight saving ends, so MT wall-clock times are not strictly ordered.
        ,event_at_utc AS valid_from_utc
        ,next_event_at_utc AS valid_to_utc
        ,event_at_mt AS valid_from_mt
        ,next_event_at_mt AS valid_to_mt
        ,next_event_at_utc IS NULL AS is_current
        -- Valid paths: (start) -> trial -> subscribed -> churned.
        ,CASE
            WHEN previous_lifecycle_state IS NULL AND lifecycle_state = 'trial' THEN TRUE
            WHEN previous_lifecycle_state = 'trial' AND lifecycle_state = 'subscribed' THEN TRUE
            WHEN previous_lifecycle_state = 'subscribed' AND lifecycle_state = 'churned' THEN TRUE
            ELSE FALSE
        END AS is_valid_transition
        ,DATEDIFF(
            DAY
            ,event_at_mt
            ,COALESCE(
                next_event_at_mt
                ,DATEADD(DAY, 1, CAST('{{ var("reporting_end_date") }}' AS TIMESTAMP_NTZ))
            )
        ) AS days_in_state
    FROM with_neighbours

)

SELECT *
FROM final
