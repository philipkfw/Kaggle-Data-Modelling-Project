{{ config(severity='warn') }}

-- Known data quality issue: invoices and payments dated after the account churned.
-- Records are kept in all metrics and flagged with is_post_churn_activity.
-- This test surfaces the count on every run.

SELECT
    'invoice' AS record_type
    ,invoice_id AS record_id
    ,account_id
FROM {{ ref('fct_invoices') }}
WHERE is_post_churn_activity

UNION ALL

SELECT
    'payment' AS record_type
    ,transaction_id AS record_id
    ,account_id
FROM {{ ref('fct_payment_transactions') }}
WHERE is_post_churn_activity
