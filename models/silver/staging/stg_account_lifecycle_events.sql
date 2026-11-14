-- Grain: one row per account lifecycle event.
-- The source has no event identifier, so a surrogate key is derived from the
-- natural key (account_id, event_time), which tests confirm is unique.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'account_lifecycle_events') }}

)

,standardised AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['account_id', 'event_time']) }} AS lifecycle_event_id
        ,TRIM(account_id) AS account_id
        ,LOWER(TRIM(lifecycle_state)) AS lifecycle_state
        ,event_time AS event_at_utc
        ,{{ to_mountain_time('event_time') }} AS event_at_mt
        ,TO_DATE({{ to_mountain_time('event_time') }}) AS event_date_mt
        ,_source_file AS source_file
        ,_loaded_at AS loaded_at
    FROM source

)

SELECT *
FROM standardised
