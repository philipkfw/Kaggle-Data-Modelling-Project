-- Grain: one row per payment transaction.
-- Converts to USD at the transaction date (MT), classifies the payment channel,
-- and records the account's lifecycle stage when the payment was made.

WITH payments AS (

    SELECT *
    FROM {{ ref('stg_payment_transactions') }}

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
        payments.transaction_id
        ,payments.account_id
        ,payments.invoice_id
        ,payments.transaction_at_utc
        ,payments.transaction_at_mt
        ,payments.transaction_date_mt
        ,payments.payment_method
        -- Electronic = processed through a payment rail; offline = recorded manually.
        ,CASE
            WHEN payments.payment_method IN ('Credit Card', 'ACH', 'Paypal') THEN 'electronic'
            WHEN payments.payment_method IN ('Cash', 'Cheque') THEN 'offline'
            ELSE 'unknown'
        END AS payment_channel
        ,payments.payment_amount
        ,payments.currency_code
        ,fx_rates.exchange_rate
        ,fx_rates.rate_effective_date AS fx_rate_effective_date
        ,fx_rates.rate_source AS fx_rate_source
        ,CAST(payments.payment_amount * fx_rates.exchange_rate AS NUMBER(38, 6)) AS amount_usd
        ,COALESCE(lifecycle.lifecycle_state, 'pre_trial') AS lifecycle_stage_at_payment
        ,COALESCE(lifecycle.lifecycle_state, 'pre_trial') = 'churned' AS is_post_churn_activity
    FROM payments
    -- LEFT JOIN so a missing rate surfaces as a NULL USD amount (caught by tests).
    LEFT JOIN fx_rates
        ON payments.currency_code = fx_rates.from_currency
        AND payments.transaction_date_mt = fx_rates.rate_date
    -- Non-overlapping intervals (tested) guarantee at most one match.
    LEFT JOIN lifecycle
        ON payments.account_id = lifecycle.account_id
        AND payments.transaction_at_utc >= lifecycle.valid_from_utc
        AND (
            lifecycle.valid_to_utc IS NULL
            OR payments.transaction_at_utc < lifecycle.valid_to_utc
        )

)

SELECT *
FROM joined
