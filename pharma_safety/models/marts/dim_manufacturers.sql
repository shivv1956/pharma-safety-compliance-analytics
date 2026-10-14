-- One row per conformed manufacturer (subsidiaries rolled up to the parent).
-- Built from int_manufacturer_resolution; the flags show which sources know the manufacturer.

select
    manufacturer_key,
    max(manufacturer_name)                                      as manufacturer_name,
    max(manufacturer_match_key)                                 as manufacturer_match_key,
    count(*)                                                    as source_name_count,
    boolor_agg(source_system = 'payments')                      as in_payments,
    boolor_agg(source_system = 'recalls')                       as in_recalls,
    boolor_agg(source_system = 'adverse_events')                as in_adverse_events
from {{ ref('int_manufacturer_resolution') }}
group by manufacturer_key
