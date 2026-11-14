-- Grain: one row per invoice.
-- Authoritative source for Invoice Volume (COUNT DISTINCT invoice_id) and
-- Invoice Dollar Volume (SUM invoice_amount_usd). Join to dim_accounts on account_id.

WITH invoices AS (

    SELECT *
    FROM {{ ref('int_invoices') }}

)

,final AS (

    SELECT
        invoice_id
        ,account_id
        ,invoice_created_at_mt
        ,invoice_created_date_mt
        ,invoice_sent_at_mt
        ,invoice_sent_date_mt
        ,invoice_amount
        ,currency_code
        ,exchange_rate
        ,fx_rate_effective_date
        ,fx_rate_source
        ,invoice_amount_usd
        ,line_item_count
        ,line_item_amount_total
        ,distinct_service_type_count
        ,is_amount_reconciled
        ,payment_count
        ,is_paid
        ,lifecycle_stage_at_invoice
        ,is_post_churn_activity
    FROM invoices

)

SELECT *
FROM final
