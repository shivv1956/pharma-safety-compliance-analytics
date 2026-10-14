{{
    config(
        materialized='incremental',
        unique_key='recall_number',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

-- One row per classified drug recall. A recall whose status changes (ongoing -> terminated)
-- is reloaded by ingestion, and the merge updates the row.
-- Incremental on `_loaded_at`; re-run with --full-refresh after changing the alias seed.

with recalls as (

    select * from {{ ref('stg_recalls') }}
    {% if is_incremental() %}
    where _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}

)

select
    recalls.recall_number,
    recalls.recall_event_id,
    manufacturers.manufacturer_key,
    drugs.drug_key,
    to_number(to_char(recalls.report_date, 'YYYYMMDD'))         as date_key,
    recalls.report_date,
    recalls.recall_initiation_date,
    recalls.classification_date,
    recalls.termination_date,
    recalls.recall_classification,
    recalls.recall_severity_rank,
    recalls.is_class_i,
    recalls.recall_status,
    recalls.recall_status = 'Ongoing'                           as is_ongoing,
    recalls.voluntary_or_mandated,
    recalls.recall_reason,
    recalls.product_description,
    recalls.distribution_pattern,
    recalls._loaded_at
from recalls
left join {{ ref('int_recall_drug_names') }} as recall_names
    on recall_names.recall_number = recalls.recall_number
left join {{ ref('int_manufacturer_resolution') }} as manufacturers
    on manufacturers.source_system = 'recalls'
    and manufacturers.raw_name = recalls.recalling_firm
left join {{ ref('int_drug_resolution') }} as drugs
    on drugs.source_system = 'recalls'
    and drugs.raw_name = recall_names.raw_name
