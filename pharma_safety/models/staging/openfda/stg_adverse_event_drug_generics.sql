-- Generic (active ingredient) name(s) openFDA matched to each FAERS drug (the
-- `openfda.generic_name` array, one row per element). Position 0 is used as the drug's generic.

select
    _dlt_parent_id                          as adverse_event_drug_id,
    _dlt_list_idx                           as generic_position,
    nullif(trim(value), '')                 as generic_name
from {{ source('openfda', 'adverse_events__patient__drug__openfda__generic_name') }}
where nullif(trim(value), '') is not null
