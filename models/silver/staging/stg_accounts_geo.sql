-- Grain: one row per account (uniqueness enforced by tests).
-- Keeps the source country value and adds ISO country and expected currency codes.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'accounts_geo') }}

)

,country_reference AS (

    SELECT *
    FROM {{ ref('country_reference') }}

)

,standardised AS (

    SELECT
        TRIM(source.account_id) AS account_id
        ,TRIM(source.country) AS country
        ,country_reference.country_code
        ,country_reference.currency_code AS country_currency_code
        ,TRIM(source.region) AS region
        ,TRIM(source.city) AS city
        ,source._source_file AS source_file
        ,source._loaded_at AS loaded_at
    FROM source
    LEFT JOIN country_reference
        ON TRIM(source.country) = country_reference.source_country_name

)

SELECT *
FROM standardised
