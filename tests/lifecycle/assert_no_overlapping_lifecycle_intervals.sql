-- An account's lifecycle intervals must never overlap; otherwise an account
-- could be counted in two stages at once. Compared in UTC (strictly ordered).

SELECT
    earlier.account_id
    ,earlier.lifecycle_event_id AS first_event_id
    ,later.lifecycle_event_id AS second_event_id
FROM {{ ref('int_account_lifecycle') }} AS earlier
INNER JOIN {{ ref('int_account_lifecycle') }} AS later
    ON earlier.account_id = later.account_id
    AND earlier.lifecycle_event_id <> later.lifecycle_event_id
    AND earlier.valid_from_utc <= later.valid_from_utc
WHERE earlier.valid_to_utc IS NULL
    OR earlier.valid_to_utc > later.valid_from_utc
