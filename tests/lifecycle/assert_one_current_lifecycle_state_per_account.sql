-- Every account with lifecycle history must have exactly one current state.

SELECT
    account_id
    ,COUNT_IF(is_current) AS current_state_count
FROM {{ ref('fct_account_lifecycle') }}
GROUP BY account_id
HAVING COUNT_IF(is_current) <> 1
