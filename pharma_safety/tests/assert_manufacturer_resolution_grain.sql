-- int_manufacturer_resolution must have exactly one row per (source_system, raw_name),
-- and every manufacturer must have exactly one display name.
select source_system, raw_name, count(*) as n
from {{ ref('int_manufacturer_resolution') }}
group by 1, 2
having count(*) > 1

union all

select 'display_name', manufacturer_key, count(distinct manufacturer_name)
from {{ ref('int_manufacturer_resolution') }}
group by 1, 2
having count(distinct manufacturer_name) > 1
