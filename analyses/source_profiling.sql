-- Phase 1 source profiling: the discovery checks behind docs/data_quality.md.
-- Compile with `dbt compile --select source_profiling` and run each statement in
-- Snowflake. Read-only; never materialised.

-- 1. Primary key uniqueness (expected: 0 duplicates everywhere)
SELECT
    'accounts.id' AS key_name
    ,COUNT(*) - COUNT(DISTINCT id) AS duplicate_keys
FROM {{ source('bronze', 'accounts') }}
UNION ALL
SELECT
    'accounts_geo.account_id'
    ,COUNT(*) - COUNT(DISTINCT account_id)
FROM {{ source('bronze', 'accounts_geo') }}
UNION ALL
SELECT
    'account_lifecycle_events (account_id, event_time)'
    ,COUNT(*) - COUNT(DISTINCT account_id, event_time)
FROM {{ source('bronze', 'account_lifecycle_events') }}
UNION ALL
SELECT
    'invoices.invoice_id'
    ,COUNT(*) - COUNT(DISTINCT invoice_id)
FROM {{ source('bronze', 'invoices') }}
UNION ALL
SELECT
    'invoice_line_items.id'
    ,COUNT(*) - COUNT(DISTINCT id)
FROM {{ source('bronze', 'invoice_line_items') }}
UNION ALL
SELECT
    'payment_transactions.transaction_id'
    ,COUNT(*) - COUNT(DISTINCT transaction_id)
FROM {{ source('bronze', 'payment_transactions') }};

-- 2. Payments per invoice (expected: 0 or 1; the model doesn't assume this)
SELECT
    payments_per_invoice
    ,COUNT(*) AS invoices
FROM (
    SELECT
        invoices.invoice_id
        ,COUNT(payments.transaction_id) AS payments_per_invoice
    FROM {{ source('bronze', 'invoices') }} AS invoices
    LEFT JOIN {{ source('bronze', 'payment_transactions') }} AS payments
        ON invoices.invoice_id = payments.invoice_id
    GROUP BY invoices.invoice_id
)
GROUP BY payments_per_invoice
ORDER BY payments_per_invoice;

-- 3. Currencies per account and country (expected: exactly 1, mapped 1:1 to country)
SELECT
    geo.country
    ,invoices.currency
    ,COUNT(DISTINCT invoices.account_id) AS accounts
    ,COUNT(*) AS invoices
FROM {{ source('bronze', 'invoices') }} AS invoices
INNER JOIN {{ source('bronze', 'accounts_geo') }} AS geo
    ON invoices.account_id = geo.account_id
GROUP BY
    geo.country
    ,invoices.currency
ORDER BY geo.country;

-- 4. Lifecycle paths (expected: trial > subscribed > churned, or a prefix of it)
SELECT
    lifecycle_path
    ,COUNT(*) AS accounts
FROM (
    SELECT
        account_id
        ,LISTAGG(lifecycle_state, ' > ') WITHIN GROUP (ORDER BY event_time) AS lifecycle_path
    FROM {{ source('bronze', 'account_lifecycle_events') }}
    GROUP BY account_id
)
GROUP BY lifecycle_path
ORDER BY accounts DESC;

-- 5. Timezone evidence: hour-of-day by country. A local-time source would cluster
--    in business hours; the observed distribution is near-uniform (source assumed UTC).
SELECT
    geo.country
    ,COUNT_IF(HOUR(invoices.invoice_created_time) BETWEEN 0 AND 5) AS hours_00_05
    ,COUNT_IF(HOUR(invoices.invoice_created_time) BETWEEN 6 AND 11) AS hours_06_11
    ,COUNT_IF(HOUR(invoices.invoice_created_time) BETWEEN 12 AND 17) AS hours_12_17
    ,COUNT_IF(HOUR(invoices.invoice_created_time) BETWEEN 18 AND 23) AS hours_18_23
FROM {{ source('bronze', 'invoices') }} AS invoices
INNER JOIN {{ source('bronze', 'accounts_geo') }} AS geo
    ON invoices.account_id = geo.account_id
GROUP BY geo.country
ORDER BY geo.country;

-- 6. Activity after churn (DQ1) and stale trials (DQ2)
WITH churn AS (

    SELECT
        account_id
        ,event_time AS churned_at
    FROM {{ source('bronze', 'account_lifecycle_events') }}
    WHERE lifecycle_state = 'churned'

)

SELECT
    'invoices after churn' AS finding
    ,COUNT(*) AS records
FROM {{ source('bronze', 'invoices') }} AS invoices
INNER JOIN churn
    ON invoices.account_id = churn.account_id
WHERE invoices.invoice_created_time > churn.churned_at
UNION ALL
SELECT
    'payments after churn'
    ,COUNT(*)
FROM {{ source('bronze', 'payment_transactions') }} AS payments
INNER JOIN churn
    ON payments.account_id = churn.account_id
WHERE payments.transaction_time > churn.churned_at;
