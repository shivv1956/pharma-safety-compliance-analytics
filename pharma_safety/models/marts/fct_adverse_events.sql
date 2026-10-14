{{
    config(
        materialized='incremental',
        unique_key='adverse_event_drug_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

-- One row per (FAERS report, drug): about 12.9M rows. Report-level facts (seriousness,
-- reporter, patient) repeat on each drug row, so count reports with
-- count(distinct adverse_event_report_id), and filter on `is_suspect` for the drugs a
-- reporter blamed.
-- `manufacturer_key` comes from openFDA's first manufacturer for the drug; it is null for
-- the ~17% of drug rows openFDA could not match.
-- Incremental on the report's `_loaded_at`; re-run with --full-refresh after changing the
-- alias seed.

with events as (

    select * from {{ ref('stg_adverse_events') }}
    {% if is_incremental() %}
    where _loaded_at > (select coalesce(max(_loaded_at), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}

),

reaction_counts as (

    select
        reactions.adverse_event_report_id,
        count(*) as reaction_count
    from {{ ref('stg_adverse_event_reactions') }} as reactions
    inner join events
        on events.adverse_event_report_id = reactions.adverse_event_report_id
    group by 1

)

select
    drugs.adverse_event_drug_id,
    drugs.adverse_event_report_id,
    drug_resolution.drug_key,
    manufacturer_resolution.manufacturer_key,
    to_number(to_char(events.received_date, 'YYYYMMDD'))        as date_key,
    events.received_date,
    drugs.drug_role,
    drugs.drug_role = 'suspect'                                 as is_suspect,
    events.is_serious,
    events.is_death,
    events.is_life_threatening,
    events.is_hospitalization,
    events.is_disabling,
    events.is_congenital_anomaly,
    events.is_other_serious,
    events.reporter_qualification,
    events.patient_sex,
    events.patient_age,
    events.patient_age_unit_code,
    coalesce(reaction_counts.reaction_count, 0)                 as reaction_count,
    events._loaded_at
from {{ ref('stg_adverse_event_drugs') }} as drugs
inner join events
    on events.adverse_event_report_id = drugs.adverse_event_report_id
left join reaction_counts
    on reaction_counts.adverse_event_report_id = drugs.adverse_event_report_id
left join {{ source('openfda', 'adverse_events__patient__drug__openfda__manufacturer_name') }} as openfda_manufacturer
    on openfda_manufacturer._dlt_parent_id = drugs.adverse_event_drug_id
    and openfda_manufacturer._dlt_list_idx = 0
left join {{ ref('int_manufacturer_resolution') }} as manufacturer_resolution
    on manufacturer_resolution.source_system = 'adverse_events'
    and manufacturer_resolution.raw_name = trim(openfda_manufacturer.value)
left join {{ ref('int_drug_resolution') }} as drug_resolution
    on drug_resolution.source_system = 'adverse_events'
    and drug_resolution.raw_name = drugs.drug_name_upper
