-- Grain: one row per payment transaction.
-- Authoritative source for Gross Payment Volume (SUM amount_usd).
-- Join to dim_accounts on account_id; never join directly to fct_invoices.

WITH payments AS (

    SELECT *
    FROM {{ ref('int_payment_transactions') }}

)

,final AS (

    SELECT
        transaction_id
        ,account_id
        ,invoice_id
        ,transaction_at_mt
        ,transaction_date_mt
        ,payment_method
        ,payment_channel
        ,payment_amount
        ,currency_code
        ,exchange_rate
        ,fx_rate_effective_date
        ,fx_rate_source
        ,amount_usd
        ,lifecycle_stage_at_payment
        ,is_post_churn_activity
    FROM payments

)

SELECT *
FROM final
