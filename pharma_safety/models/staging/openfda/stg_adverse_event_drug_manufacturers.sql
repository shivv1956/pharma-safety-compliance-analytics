-- Manufacturer name(s) openFDA matched to each FAERS drug (the `openfda.manufacturer_name`
-- array, one row per element). Position 0 is the drug's primary manufacturer.
-- The source table has ~170M rows: filter by `adverse_event_drug_id` or aggregate.

select
    _dlt_parent_id                          as adverse_event_drug_id,
    _dlt_list_idx                           as manufacturer_position,
    nullif(trim(value), '')                 as manufacturer_name
from {{ source('openfda', 'adverse_events__patient__drug__openfda__manufacturer_name') }}
where nullif(trim(value), '') is not null
