-- Grain: one row per account.
-- Combines account attributes with geography. A LEFT JOIN keeps accounts that
-- have no geography; they are labelled 'Unknown' explicitly rather than dropped.

WITH accounts AS (

    SELECT *
    FROM {{ ref('stg_accounts') }}

)

,accounts_geo AS (

    SELECT *
    FROM {{ ref('stg_accounts_geo') }}

)

,enriched AS (

    SELECT
        accounts.account_id
        ,accounts.sign_up_at_utc
        ,accounts.sign_up_at_mt
        ,accounts.sign_up_date_mt
        ,COALESCE(accounts.sign_up_platform, 'Unknown') AS sign_up_platform
        ,COALESCE(accounts_geo.country, 'Unknown') AS country
        ,COALESCE(accounts_geo.country_code, 'Unknown') AS country_code
        ,accounts_geo.country_currency_code
        ,COALESCE(accounts_geo.region, 'Unknown') AS region
        ,COALESCE(accounts_geo.city, 'Unknown') AS city
        ,accounts_geo.account_id IS NOT NULL AS has_geography
    FROM accounts
    LEFT JOIN accounts_geo
        ON accounts.account_id = accounts_geo.account_id

)

SELECT *
FROM enriched
