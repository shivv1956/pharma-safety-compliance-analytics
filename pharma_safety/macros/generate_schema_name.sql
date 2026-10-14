{#-
    Use the custom schema name exactly as configured (e.g. `staging`) instead of
    dbt's default `<target.schema>_<custom>` (e.g. DBT_SHIVA_STAGING).
    Environments are separated by database (PHARMA_DEV / PHARMA_TEST / PHARMA_PROD),
    so the schema names can be the same everywhere.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
