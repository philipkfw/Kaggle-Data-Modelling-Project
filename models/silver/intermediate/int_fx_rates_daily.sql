-- Grain: one row per calendar date per currency, across the reporting window.
-- The single place where weekend/holiday FX logic lives: each calendar date takes
-- the most recent rate published ON OR BEFORE that date (never a future rate).
-- Downstream models then convert with a simple equi-join on (currency, date).

WITH date_spine AS (

    {{ dbt_utils.date_spine(
        datepart="day"
        ,start_date="CAST('" ~ var('reporting_start_date') ~ "' AS DATE)"
        ,end_date="DATEADD(DAY, 1, CAST('" ~ var('reporting_end_date') ~ "' AS DATE))"
    ) }}

)

,calendar AS (

    SELECT
        CAST(date_day AS DATE) AS rate_date
    FROM date_spine

)

,published_rates AS (

    SELECT *
    FROM {{ ref('stg_fx_rates') }}

)

,currencies AS (

    SELECT DISTINCT
        from_currency
    FROM published_rates

)

,calendar_currencies AS (

    SELECT
        calendar.rate_date
        ,currencies.from_currency
    FROM calendar
    CROSS JOIN currencies

)

,as_of_rates AS (

    SELECT
        calendar_currencies.rate_date
        ,calendar_currencies.from_currency
        ,'USD' AS to_currency
        ,published_rates.exchange_rate
        ,published_rates.rate_date AS rate_effective_date
        ,DATEDIFF(DAY, published_rates.rate_date, calendar_currencies.rate_date) AS days_since_published
        ,published_rates.source_series_id
        ,published_rates.rate_source
        ,published_rates.rate_type
        ,published_rates.loaded_at
    FROM calendar_currencies
    ASOF JOIN published_rates
        MATCH_CONDITION (calendar_currencies.rate_date >= published_rates.rate_date)
        ON calendar_currencies.from_currency = published_rates.from_currency

)

SELECT *
FROM as_of_rates
