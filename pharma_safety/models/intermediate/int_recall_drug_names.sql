-- The drug name of each recall: openFDA brand name, else openFDA generic name, else the first
-- phrase of the free-text product description. One row per recall_number.
-- Shared by int_drug_names (name inventory) and fct_recalls (drug_key lookup).

with recall_openfda as (

    select
        recalls.recall_number,
        recalls.product_description,
        names.brand_name,
        names.generic_name
    from {{ ref('stg_recalls') }} as recalls
    left join {{ ref('stg_recall_openfda_names') }} as names
        on names.recall_source_row_id = recalls._source_row_id

)

select
    recall_number,
    coalesce(
        nullif(brand_name, ''),
        nullif(generic_name, ''),
        nullif(upper(trim(regexp_substr(product_description, '^[^,(]+'))), '')
    ) as raw_name
from recall_openfda
