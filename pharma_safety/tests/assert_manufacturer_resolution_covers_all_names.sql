-- No raw name may be lost or invented by the resolution step.
select 'row_count_mismatch' as problem
from (
    select
        (select count(*) from {{ ref('int_manufacturer_names') }}) as names_n,
        (select count(*) from {{ ref('int_manufacturer_resolution') }}) as resolved_n
)
where names_n <> resolved_n
