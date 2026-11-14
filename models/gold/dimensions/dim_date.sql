-- Grain: one row per calendar date (Mountain Time) across the reporting window.
-- Serves as the date spine for point-in-time lifecycle snapshots and as a
-- standard calendar dimension for BI tools.

WITH date_spine AS (

    {{ dbt_utils.date_spine(
        datepart="day"
        ,start_date="CAST('" ~ var('reporting_start_date') ~ "' AS DATE)"
        ,end_date="DATEADD(DAY, 1, CAST('" ~ var('reporting_end_date') ~ "' AS DATE))"
    ) }}

)

,calendar AS (

    SELECT
        CAST(date_day AS DATE) AS date_day
    FROM date_spine

)

,final AS (

    SELECT
        date_day
        ,DAYOFWEEKISO(date_day) AS day_of_week_iso
        ,DAYNAME(date_day) AS day_name
        ,DAYOFWEEKISO(date_day) IN (6, 7) AS is_weekend
        ,DATEADD(DAY, 1 - DAYOFWEEKISO(date_day), date_day) AS week_start_date
        ,DATE_TRUNC('MONTH', date_day) AS month_start_date
        ,LAST_DAY(date_day, 'MONTH') AS month_end_date
        -- Last date with data in the month (the reporting end date for a partial month).
        ,LEAST(LAST_DAY(date_day, 'MONTH'), CAST('{{ var("reporting_end_date") }}' AS DATE)) AS month_reporting_end_date
        ,MONTHNAME(date_day) AS month_name
        ,TO_CHAR(date_day, 'YYYY-MM') AS year_month
        ,DATE_TRUNC('QUARTER', date_day) AS quarter_start_date
        ,QUARTER(date_day) AS quarter_number
        ,YEAR(date_day) AS year_number
        ,date_day = LAST_DAY(date_day, 'MONTH') AS is_month_end
    FROM calendar

)

SELECT *
FROM final
