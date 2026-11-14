-- Every account must have a known country, region, city and sign-up platform,
-- so segmented totals always add up to the overall total.

SELECT
    account_id
    ,country
    ,region
    ,city
    ,sign_up_platform
FROM {{ ref('dim_accounts') }}
WHERE NOT has_geography
    OR country = 'Unknown'
    OR country_code = 'Unknown'
    OR region = 'Unknown'
    OR city = 'Unknown'
    OR sign_up_platform = 'Unknown'
