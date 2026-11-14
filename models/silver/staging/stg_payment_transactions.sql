-- Grain: one row per payment transaction.
-- Original amount and currency are preserved; USD conversion happens in
-- int_payment_transactions. The source has no status, refund or reversal fields.

WITH source AS (

    SELECT *
    FROM {{ source('bronze', 'payment_transactions') }}

)

,standardised AS (

    SELECT
        TRIM(transaction_id) AS transaction_id
        ,TRIM(invoice_id) AS invoice_id
        ,TRIM(account_id) AS account_id
        ,transaction_time AS transaction_at_utc
        ,{{ to_mountain_time('transaction_time') }} AS transaction_at_mt
        ,TO_DATE({{ to_mountain_time('transaction_time') }}) AS transaction_date_mt
        ,TRIM(payment_method) AS payment_method
        ,CAST(amount AS NUMBER(18, 2)) AS payment_amount
        ,UPPER(TRIM(currency)) AS currency_code
        ,_source_file AS source_file
        ,_loaded_at AS loaded_at
    FROM source

)

SELECT *
FROM standardised
