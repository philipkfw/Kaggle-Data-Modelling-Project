{#
    Schema routing with dev/prod isolation.

    - prod target : models land in exactly the configured schema (SILVER, GOLD).
    - other targets: models land in DEV_<schema> (DEV_SILVER, DEV_GOLD), so
      development runs never overwrite production tables.

    This overrides dbt's default <target_schema>_<custom_schema> naming.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim | upper }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        DEV_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
