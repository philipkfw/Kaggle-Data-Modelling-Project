-- Grain: one row per published rate date per currency.
-- Normalises every FRED series to the convention: 1 unit of from_currency = X USD.
-- Only published dates appear here; weekend/holiday handling is in int_fx_rates_daily.

WITH source AS (

    SELECT *
    FROM {{ ref('fx_rates_fred_h10') }}

)

-- FRED quotes series in different directions, so each needs its own rule.
,series_definitions AS (

    SELECT
        column1 AS series_id
        ,column2 AS from_currency
        ,column3 AS quote_convention
    FROM VALUES
        ('DEXCAUS', 'CAD', 'foreign_per_usd')
        ,('DEXUSUK', 'GBP', 'usd_per_foreign')
        ,('DEXUSAL', 'AUD', 'usd_per_foreign')

)

,published_rates AS (

    SELECT
        source.rate_date
        ,series_definitions.from_currency
        ,'USD' AS to_currency
        ,CAST(
            CASE
                WHEN series_definitions.quote_convention = 'foreign_per_usd'
                    THEN 1 / source.observed_value
                ELSE source.observed_value
            END
            AS NUMBER(38, 10)
        ) AS exchange_rate
        ,source.series_id AS source_series_id
        ,'Federal Reserve H.10 via FRED' AS rate_source
        ,'daily_noon_buying_rate' AS rate_type
        ,CAST(source.retrieved_date AS TIMESTAMP_NTZ) AS loaded_at
    FROM source
    INNER JOIN series_definitions
        ON source.series_id = series_definitions.series_id

)

-- USD needs no conversion; identity rows keep every currency on one join path.
,usd_identity_rates AS (

    SELECT DISTINCT
        rate_date
        ,'USD' AS from_currency
        ,'USD' AS to_currency
        ,CAST(1 AS NUMBER(38, 10)) AS exchange_rate
        ,CAST(NULL AS VARCHAR) AS source_series_id
        ,'identity' AS rate_source
        ,'identity' AS rate_type
        ,loaded_at
    FROM published_rates

)

SELECT *
FROM published_rates

UNION ALL

SELECT *
FROM usd_identity_rates
