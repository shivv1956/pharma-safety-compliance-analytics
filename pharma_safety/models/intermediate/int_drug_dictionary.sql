-- Name -> generic (active ingredient) dictionary learned from the data itself.
-- Every FAERS drug row that openFDA enriched says "this reported name is this generic";
-- where openFDA did not enrich it, the reporter's own active-substance field is used.
-- For each name the most frequent generic wins. One row per name_key.

with event_pairs as (

    select
        drugs.drug_name_upper as raw_name,
        upper(trim(coalesce(generics.generic_name, drugs.active_substance_name))) as raw_generic,
        count(*) as n
    from {{ ref('stg_adverse_event_drugs') }} as drugs
    left join {{ ref('stg_adverse_event_drug_generics') }} as generics
        on generics.adverse_event_drug_id = drugs.adverse_event_drug_id
        and generics.generic_position = 0
    where drugs.drug_name_upper is not null
    group by 1, 2

),

recall_pairs as (

    select
        names.brand_name as raw_name,
        names.generic_name as raw_generic,
        count(*) as n
    from {{ ref('stg_recalls') }} as recalls
    inner join {{ ref('stg_recall_openfda_names') }} as names
        on names.recall_source_row_id = recalls._source_row_id
    where names.brand_name is not null and names.generic_name is not null
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
