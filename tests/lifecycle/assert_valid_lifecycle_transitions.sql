{{ config(severity='warn') }}

-- Flags lifecycle transitions outside (start)->trial->subscribed->churned.
-- Warn only: invalid transitions are kept and flagged, never removed, and the
-- point-in-time logic remains correct regardless.

SELECT
    lifecycle_event_id
    ,account_id
    ,event_sequence
    ,previous_lifecycle_state
    ,lifecycle_state
FROM {{ ref('fct_account_lifecycle') }}
WHERE NOT is_valid_transition
