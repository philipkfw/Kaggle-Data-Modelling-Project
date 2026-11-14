-- Grain: one row per account.
-- Standardises names and types; converts the sign-up timestamp to Mountain Time.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'accounts') }}

)

,standardised AS (

    SELECT
        TRIM(id) AS account_id
        ,sign_up_time AS sign_up_at_utc
        ,{{ to_mountain_time('sign_up_time') }} AS sign_up_at_mt
        ,TO_DATE({{ to_mountain_time('sign_up_time') }}) AS sign_up_date_mt
        ,LOWER(TRIM(sign_up_platform)) AS sign_up_platform
        ,_source_file AS source_file
        ,_loaded_at AS loaded_at
    FROM source

)

SELECT *
FROM standardised
