-- Grain: one row per calendar date per currency.
-- BI-facing view of the exact rates applied to invoices and payments, so any
-- USD amount can be audited back to its rate and publication date.

WITH fx_rates AS (

    SELECT *
    FROM {{ ref('int_fx_rates_daily') }}

)

,final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['rate_date', 'from_currency']) }} AS fx_rate_id
        ,rate_date
        ,from_currency
        ,to_currency
        ,exchange_rate
        ,rate_effective_date
        ,days_since_published
        ,source_series_id
        ,rate_source
        ,rate_type
        ,loaded_at
    FROM fx_rates

)

SELECT *
FROM final
