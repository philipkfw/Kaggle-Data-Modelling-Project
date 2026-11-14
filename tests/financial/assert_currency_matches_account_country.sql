-- Invoices and payments must be in the local currency of the account's country.
-- Guards the assumption that currency is an account-level attribute.

WITH activity AS (

    SELECT
        'invoice' AS record_type
        ,invoice_id AS record_id
        ,account_id
        ,currency_code
    FROM {{ ref('stg_invoices') }}

    UNION ALL

    SELECT
        'payment' AS record_type
        ,transaction_id AS record_id
        ,account_id
        ,currency_code
    FROM {{ ref('stg_payment_transactions') }}

)

SELECT
    activity.record_type
    ,activity.record_id
    ,activity.currency_code
    ,accounts_geo.country
    ,accounts_geo.country_currency_code
FROM activity
LEFT JOIN {{ ref('stg_accounts_geo') }} AS accounts_geo
    ON activity.account_id = accounts_geo.account_id
WHERE accounts_geo.country_currency_code IS NULL
    OR activity.currency_code <> accounts_geo.country_currency_code
