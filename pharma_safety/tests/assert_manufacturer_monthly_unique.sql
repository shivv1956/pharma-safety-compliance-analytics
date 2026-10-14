-- mart_manufacturer_monthly must have one row per (manufacturer_key, month_start).
select manufacturer_key, month_start, count(*) as n
from {{ ref('mart_manufacturer_monthly') }}
group by 1, 2
having count(*) > 1
