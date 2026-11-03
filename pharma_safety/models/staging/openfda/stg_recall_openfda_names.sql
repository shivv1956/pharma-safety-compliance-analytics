-- First brand and generic name openFDA matched to each recall (about half of recalls have any).
-- Join to stg_recalls on `recall_source_row_id` = `_source_row_id`.

with brand as (

    select _dlt_parent_id, upper(nullif(trim(value), '')) as brand_name
    from {{ source('openfda', 'recalls__openfda__brand_name') }}
    where _dlt_list_idx = 0

),

generic as (

    select _dlt_parent_id, upper(nullif(trim(value), '')) as generic_name
    from {{ source('openfda', 'recalls__openfda__generic_name') }}
    where _dlt_list_idx = 0

)

select
    coalesce(brand._dlt_parent_id, generic._dlt_parent_id)  as recall_source_row_id,
    brand.brand_name,
    generic.generic_name
from brand
full outer join generic
    on brand._dlt_parent_id = generic._dlt_parent_id
