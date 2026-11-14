{#
    Converts a timezone-naive source timestamp to Mountain Time.

    - Source zone comes from var('source_timezone') (assumed UTC).
    - Target zone comes from var('reporting_timezone') (America/Denver).
    - The 3-argument CONVERT_TIMEZONE form is independent of the session
      timezone and uses IANA rules, so MST/MDT daylight saving is handled
      automatically - no hardcoded UTC-6 / UTC-7 offsets.
    - Returns TIMESTAMP_NTZ representing Mountain Time wall-clock time.
#}
{% macro to_mountain_time(column_name) -%}
    CONVERT_TIMEZONE(
        '{{ var("source_timezone") }}'
        ,'{{ var("reporting_timezone") }}'
        ,{{ column_name }}
    )
{%- endmacro %}
