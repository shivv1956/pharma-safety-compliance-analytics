-- int_drug_resolution must have exactly one row per (source_system, raw_name), no raw name
-- may be lost or invented, and every conformed drug must have exactly one display name.
select 'duplicate_name' as problem, source_system || ':' || raw_name as detail
from {{ ref('int_drug_resolution') }}
group by source_system, raw_name
having count(*) > 1

union all

select 'row_count_mismatch', null
where (select count(*) from {{ ref('int_drug_names') }}) <> (select count(*) from {{ ref('int_drug_resolution') }})

union all

select 'multiple_display_names', drug_key
from {{ ref('int_drug_resolution') }}
group by drug_key
having count(distinct generic_name) > 1
