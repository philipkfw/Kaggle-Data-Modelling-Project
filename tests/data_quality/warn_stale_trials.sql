{{ config(severity='warn') }}

-- Known data quality issue: accounts still recorded as trial long after any trial
-- has converted. The source has no trial-expiry event, so these accounts are
-- reported as trial, exactly as recorded, and flagged with is_stale_trial.

SELECT
    account_id
    ,trial_started_date_mt
FROM {{ ref('dim_accounts') }}
WHERE is_stale_trial
