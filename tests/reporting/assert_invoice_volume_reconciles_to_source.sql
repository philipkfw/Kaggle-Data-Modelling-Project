-- Invoice Volume and Invoice Dollar Volume must reconcile from source to fact
-- to both marts.

WITH totals AS (

    SELECT
        (SELECT COUNT(DISTINCT invoice_id) FROM {{ source('bronze', 'invoices') }}) AS source_invoice_count
        ,(SELECT COUNT(DISTINCT invoice_id) FROM {{ ref('fct_invoices') }}) AS fact_invoice_count
        ,(SELECT SUM(invoice_count) FROM {{ ref('mart_financial_performance') }}) AS daily_mart_invoice_count
        ,(SELECT SUM(invoice_count) FROM {{ ref('mart_account_performance') }}) AS monthly_mart_invoice_count
        ,(SELECT SUM(invoice_amount_usd) FROM {{ ref('fct_invoices') }}) AS fact_invoice_amount_usd
        ,(SELECT SUM(invoice_amount_usd) FROM {{ ref('mart_financial_performance') }}) AS daily_mart_invoice_amount_usd
        ,(SELECT SUM(invoice_amount_usd) FROM {{ ref('mart_account_performance') }}) AS monthly_mart_invoice_amount_usd

)

SELECT
    'source_vs_fact_count' AS check_name
    ,source_invoice_count AS expected_value
    ,fact_invoice_count AS actual_value
FROM totals
WHERE source_invoice_count <> fact_invoice_count

UNION ALL

SELECT
    'fact_vs_daily_mart_count' AS check_name
    ,fact_invoice_count AS expected_value
    ,daily_mart_invoice_count AS actual_value
FROM totals
WHERE fact_invoice_count <> daily_mart_invoice_count

UNION ALL

SELECT
    'fact_vs_monthly_mart_count' AS check_name
    ,fact_invoice_count AS expected_value
    ,monthly_mart_invoice_count AS actual_value
FROM totals
WHERE fact_invoice_count <> monthly_mart_invoice_count

UNION ALL

SELECT
    'fact_vs_daily_mart_amount_usd' AS check_name
    ,fact_invoice_amount_usd AS expected_value
    ,daily_mart_invoice_amount_usd AS actual_value
FROM totals
WHERE ABS(fact_invoice_amount_usd - daily_mart_invoice_amount_usd) > 0.01

UNION ALL

SELECT
    'fact_vs_monthly_mart_amount_usd' AS check_name
    ,fact_invoice_amount_usd AS expected_value
    ,monthly_mart_invoice_amount_usd AS actual_value
FROM totals
WHERE ABS(fact_invoice_amount_usd - monthly_mart_invoice_amount_usd) > 0.01
