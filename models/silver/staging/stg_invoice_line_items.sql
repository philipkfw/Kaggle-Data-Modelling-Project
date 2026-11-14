-- Grain: one row per invoice line item.
-- Line items carry no currency; they inherit the parent invoice's currency.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'invoice_line_items') }}

)

,standardised AS (

    SELECT
        TRIM(id) AS invoice_line_item_id
        ,TRIM(invoice_id) AS invoice_id
        ,LOWER(TRIM(service_type)) AS service_type
        ,CAST(amount AS NUMBER(18, 2)) AS line_item_amount
        ,_source_file AS source_file
        ,_loaded_at AS loaded_at
    FROM source

)

SELECT *
FROM standardised
