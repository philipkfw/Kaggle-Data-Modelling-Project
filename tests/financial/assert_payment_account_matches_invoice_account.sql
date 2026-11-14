-- A payment's account_id must match the account on the invoice it pays.
-- Payments store account_id redundantly, so the two paths must agree.

SELECT
    payments.transaction_id
    ,payments.account_id AS payment_account_id
    ,invoices.account_id AS invoice_account_id
FROM {{ ref('fct_payment_transactions') }} AS payments
INNER JOIN {{ ref('fct_invoices') }} AS invoices
    ON payments.invoice_id = invoices.invoice_id
WHERE payments.account_id <> invoices.account_id
