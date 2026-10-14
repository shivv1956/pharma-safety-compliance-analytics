-- Name -> generic (active ingredient) dictionary learned from the data itself.
-- Every FAERS drug row that openFDA enriched says "this reported name is this generic";
-- where openFDA did not enrich it, the reporter's own active-substance field is used.
-- For each name the most frequent generic wins. One row per name_key.

with event_pairs as (

    select
        drugs.drug_name_upper as raw_name,
        upper(trim(coalesce(generic.value, drugs.active_substance_name))) as raw_generic,
        count(*) as n
    from {{ ref('stg_adverse_event_drugs') }} as drugs
    left join {{ source('openfda', 'adverse_events__patient__drug__openfda__generic_name') }} as generic
        on generic._dlt_parent_id = drugs.adverse_event_drug_id
        and generic._dlt_list_idx = 0
    where drugs.drug_name_upper is not null
    group by 1, 2

),

recall_pairs as (

    select
        upper(trim(brand.value)) as raw_name,
        upper(trim(generic.value)) as raw_generic,
        count(*) as n
    from {{ ref('stg_recalls') }} as recalls
    inner join {{ source('openfda', 'recalls__openfda__generic_name') }} as generic
        on generic._dlt_parent_id = recalls._source_row_id and generic._dlt_list_idx = 0
    inner join {{ source('openfda', 'recalls__openfda__brand_name') }} as brand
        on brand._dlt_parent_id = recalls._source_row_id and brand._dlt_list_idx = 0
    group by 1, 2

),

pairs as (

    select * from event_pairs
    union all
    select * from recall_pairs

),

keyed as (

    select
        {{ normalize_drug_name('raw_name') }} as name_key,
        {{ normalize_drug_name('raw_generic') }} as generic_key,
        raw_generic,
        n
    from pairs
    where nullif(raw_generic, '') is not null

),

counted as (

    select
        name_key,
        generic_key,
        sum(n) as pair_count,
        max_by(raw_generic, n) as generic_name
    from keyed
    group by 1, 2

)

select
    name_key,
    generic_key,
    generic_name,
    pair_count
from counted
qualify row_number() over (partition by name_key order by pair_count desc, generic_key) = 1
