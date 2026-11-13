{#
  By default dbt builds custom schemas as <target_schema>_<custom_schema>
  (e.g. SILVER_SILVER). Override so models land in exactly the schema
  configured in dbt_project.yml: SILVER or GOLD.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
