-- Every currency must have exactly one FX rate for every date in the reporting
-- window, so no invoice or payment can miss a conversion.

WITH expected AS (

    SELECT
        COUNT(date_day) AS expected_days
    FROM {{ ref('dim_date') }}

)

,actual AS (

    SELECT
        from_currency
        ,COUNT(rate_date) AS actual_days
        ,COUNT(exchange_rate) AS days_with_rate
    FROM {{ ref('int_fx_rates_daily') }}
    GROUP BY from_currency

)

SELECT
    actual.from_currency
    ,actual.actual_days
    ,actual.days_with_rate
    ,expected.expected_days
FROM actual
CROSS JOIN expected
WHERE actual.actual_days <> expected.expected_days
    OR actual.days_with_rate <> expected.expected_days
