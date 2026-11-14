-- Grain: one row per invoice.
-- Line items and payments are each aggregated to invoice grain BEFORE joining,
-- so neither can duplicate invoice rows. Converts to USD at the invoice created
-- date (MT) and records the account's lifecycle stage when the invoice was created.

WITH invoices AS (

    SELECT *
    FROM {{ ref('stg_invoices') }}

)

,line_item_totals AS (

    SELECT
        invoice_id
        ,COUNT(invoice_line_item_id) AS line_item_count
        ,SUM(line_item_amount) AS line_item_amount_total
        ,COUNT(DISTINCT service_type) AS distinct_service_type_count
    FROM {{ ref('stg_invoice_line_items') }}
    GROUP BY invoice_id

)

,payment_totals AS (

    SELECT
        invoice_id
        ,COUNT(transaction_id) AS payment_count
    FROM {{ ref('stg_payment_transactions') }}
    GROUP BY invoice_id

)

,fx_rates AS (

    SELECT *
    FROM {{ ref('int_fx_rates_daily') }}

)

,lifecycle AS (

    SELECT *
    FROM {{ ref('int_account_lifecycle') }}

)

,joined AS (

    SELECT
        invoices.invoice_id
        ,invoices.account_id
        ,invoices.invoice_created_at_utc
        ,invoices.invoice_created_at_mt
        ,invoices.invoice_created_date_mt
        ,invoices.invoice_sent_at_utc
        ,invoices.invoice_sent_at_mt
        ,invoices.invoice_sent_date_mt
        ,invoices.invoice_amount
        ,invoices.currency_code
        ,fx_rates.exchange_rate
        ,fx_rates.rate_effective_date AS fx_rate_effective_date
        ,fx_rates.rate_source AS fx_rate_source
        ,CAST(invoices.invoice_amount * fx_rates.exchange_rate AS NUMBER(38, 6)) AS invoice_amount_usd
        ,COALESCE(line_item_totals.line_item_count, 0) AS line_item_count
        ,COALESCE(line_item_totals.line_item_amount_total, 0) AS line_item_amount_total
        ,COALESCE(line_item_totals.distinct_service_type_count, 0) AS distinct_service_type_count
        ,invoices.invoice_amount = COALESCE(line_item_totals.line_item_amount_total, 0) AS is_amount_reconciled
        ,COALESCE(payment_totals.payment_count, 0) AS payment_count
        ,COALESCE(payment_totals.payment_count, 0) > 0 AS is_paid
        ,COALESCE(lifecycle.lifecycle_state, 'pre_trial') AS lifecycle_stage_at_invoice
        ,COALESCE(lifecycle.lifecycle_state, 'pre_trial') = 'churned' AS is_post_churn_activity
    FROM invoices
    LEFT JOIN line_item_totals
        ON invoices.invoice_id = line_item_totals.invoice_id
    LEFT JOIN payment_totals
        ON invoices.invoice_id = payment_totals.invoice_id
    -- LEFT JOIN so a missing rate surfaces as a NULL USD amount (caught by tests)
    -- instead of silently dropping the invoice.
    LEFT JOIN fx_rates
        ON invoices.currency_code = fx_rates.from_currency
        AND invoices.invoice_created_date_mt = fx_rates.rate_date
    -- Non-overlapping intervals (tested) guarantee at most one match.
    LEFT JOIN lifecycle
        ON invoices.account_id = lifecycle.account_id
        AND invoices.invoice_created_at_utc >= lifecycle.valid_from_utc
        AND (
            lifecycle.valid_to_utc IS NULL
            OR invoices.invoice_created_at_utc < lifecycle.valid_to_utc
        )

)

SELECT *
FROM joined
