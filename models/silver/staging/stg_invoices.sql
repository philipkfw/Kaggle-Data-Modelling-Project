-- Grain: one row per invoice.
-- Original amount and currency are preserved; USD conversion happens in int_invoices.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'invoices') }}

)

,standardised AS (

    SELECT
        TRIM(invoice_id) AS invoice_id
        ,TRIM(account_id) AS account_id
        ,invoice_created_time AS invoice_created_at_utc
        ,{{ to_mountain_time('invoice_created_time') }} AS invoice_created_at_mt
        ,TO_DATE({{ to_mountain_time('invoice_created_time') }}) AS invoice_created_date_mt
        ,invoice_sent_time AS invoice_sent_at_utc
        ,{{ to_mountain_time('invoice_sent_time') }} AS invoice_sent_at_mt
        ,TO_DATE({{ to_mountain_time('invoice_sent_time') }}) AS invoice_sent_date_mt
        ,CAST(amount AS NUMBER(18, 2)) AS invoice_amount
        ,UPPER(TRIM(currency)) AS currency_code
        ,_source_file AS source_file
        ,_loaded_at AS loaded_at
    FROM source

)

SELECT *
FROM standardised
