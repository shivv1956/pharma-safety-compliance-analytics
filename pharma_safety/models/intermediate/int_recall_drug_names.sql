-- The drug name of each recall: openFDA brand name, else openFDA generic name, else the first
-- phrase of the free-text product description. One row per recall_number.
-- Shared by int_drug_names (name inventory) and fct_recalls (drug_key lookup).

with recall_openfda as (

    select
        recalls.recall_number,
        recalls.product_description,
        upper(trim(brand.value)) as brand_name,
        upper(trim(generic.value)) as generic_name
    from {{ ref('stg_recalls') }} as recalls
    left join {{ source('openfda', 'recalls__openfda__brand_name') }} as brand
        on brand._dlt_parent_id = recalls._source_row_id and brand._dlt_list_idx = 0
    left join {{ source('openfda', 'recalls__openfda__generic_name') }} as generic
        on generic._dlt_parent_id = recalls._source_row_id and generic._dlt_list_idx = 0

)

select
    recall_number,
    coalesce(
        nullif(brand_name, ''),
        nullif(generic_name, ''),
        nullif(upper(trim(regexp_substr(product_description, '^[^,(]+'))), '')
    ) as raw_name
from recall_openfda
