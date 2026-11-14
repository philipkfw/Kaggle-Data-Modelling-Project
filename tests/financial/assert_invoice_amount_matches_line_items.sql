-- Every invoice amount must equal the sum of its line items.
-- Returns failing invoices.

SELECT
    invoice_id
    ,invoice_amount
    ,line_item_amount_total
    ,line_item_count
FROM {{ ref('fct_invoices') }}
WHERE NOT is_amount_reconciled
