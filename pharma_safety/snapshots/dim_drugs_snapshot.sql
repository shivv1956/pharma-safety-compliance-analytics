{% snapshot dim_drugs_snapshot %}
{{
    config(
        target_schema='snapshots',
        unique_key='drug_key',
        strategy='check',
        check_cols=['generic_name', 'primary_brand_name', 'in_payments', 'in_recalls', 'in_adverse_events']
    )
}}

-- SCD2 history of each conformed drug. The data has no marketing-status field, so this
-- tracks the attributes that do change: the primary brand and which sources list the drug.
select * from {{ ref('dim_drugs') }}

{% endsnapshot %}
