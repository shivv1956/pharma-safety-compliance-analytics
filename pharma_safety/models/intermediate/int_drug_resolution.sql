-- Maps every raw drug name, in every source, to one conformed drug (active ingredient).
--
--   dictionary   the name is known (int_drug_dictionary) -> its most common generic
--   generic      the name already is a generic known to the dictionary
--   name         nothing is known about the name; it stands for itself
--
-- Brand names therefore roll up to their generic (Humira -> adalimumab), so a manufacturer's
-- payments for a brand can be compared with adverse events reported under the generic or
-- under other brands of the same ingredient.

with names as (

    select * from {{ ref('int_drug_names') }}

),

dictionary as (

    select * from {{ ref('int_drug_dictionary') }}

),

known_generics as (

    select distinct generic_key from dictionary

),

resolved as (

    select
        names.source_system,
        names.raw_name,
        names.row_count,
        names.name_key,
        case
            when dictionary.generic_key is not null then dictionary.generic_key
            else names.name_key
        end as drug_match_key,
        case
            when dictionary.generic_key is not null then 'dictionary'
            when known_generics.generic_key is not null then 'generic'
            else 'name'
        end as match_method
    from names
    left join dictionary
        on names.name_key = dictionary.name_key
    left join known_generics
        on names.name_key = known_generics.generic_key

)

select
    source_system,
    raw_name,
    row_count,
    name_key,
    md5(drug_match_key) as drug_key,
    drug_match_key,
    drug_match_key as generic_name,
    match_method
from resolved
