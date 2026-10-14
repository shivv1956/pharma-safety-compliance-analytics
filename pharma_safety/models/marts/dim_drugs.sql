-- One row per conformed drug (active ingredient; brands roll up to their generic).
-- `primary_brand_name` is the most frequent brand name on payments, when there is one.

select
    drug_key,
    max(generic_name)                                           as generic_name,
    count(*)                                                    as source_name_count,
    max_by(iff(source_system = 'payments', raw_name, null), iff(source_system = 'payments', row_count, null))
                                                                as primary_brand_name,
    boolor_agg(source_system = 'payments')                      as in_payments,
    boolor_agg(source_system = 'recalls')                       as in_recalls,
    boolor_agg(source_system = 'adverse_events')                as in_adverse_events
from {{ ref('int_drug_resolution') }}
group by drug_key
