-- Maps every raw manufacturer name, in every source, to one conformed manufacturer.
--
--   rule   normalize_firm_name(): casing, punctuation, legal suffixes, roll-up to parent
--   alias  the manufacturer_aliases seed, for same-company names the rules cannot link
--   fuzzy  a key seen in only one source that closely matches a key from another source
--          (Jaro-Winkler). Merged only when the score is >= strong_threshold, or >=
--          fuzzy_merge_threshold and the first word matches (company-name variants such as
--          'NOVO NORDISK AS'). A one-letter difference alone is not enough: BETCO / BESTCO and
--          EXELAN / EXELA are different companies. Other near-matches are not merged; they
--          are reported in review_candidate_key / review_score for a human to confirm
--          (add confirmed pairs to the manufacturer_aliases seed).

{% set strong_threshold = 97 %}
{% set fuzzy_merge_threshold = 95 %}
{% set review_threshold = 88 %}

with names as (

    select * from {{ ref('int_manufacturer_names') }}

),

aliases as (

    select * from {{ ref('manufacturer_aliases') }}

),

ruled as (

    select
        names.source_system,
        names.raw_name,
        names.row_count,
        names.name_key,
        coalesce(aliases.canonical_key, names.name_key) as rule_key,
        iff(aliases.canonical_key is not null, 'alias', 'rule') as match_method
    from names
    left join aliases
        on names.name_key = aliases.name_key

),

keys as (

    select
        rule_key,
        count(distinct source_system) as source_count,
        min(source_system) as only_source,
        sum(row_count) as total_rows
    from ruled
    group by 1

),

fuzzy_candidates as (

    -- single-source keys against keys that exist in some other source
    select
        orphan.rule_key as orphan_key,
        candidate.rule_key as candidate_key,
        jarowinkler_similarity(orphan.rule_key, candidate.rule_key) as score,
        split_part(orphan.rule_key, ' ', 1) = split_part(candidate.rule_key, ' ', 1) as same_first_word
    from keys as orphan
    inner join keys as candidate
        on candidate.rule_key <> orphan.rule_key
        and (candidate.source_count > 1 or candidate.only_source <> orphan.only_source)
    where orphan.source_count = 1
        and length(orphan.rule_key) >= 5
        and length(candidate.rule_key) >= 5
    qualify row_number() over (
        partition by orphan.rule_key
        order by score desc, candidate.total_rows desc, candidate.rule_key
    ) = 1

),

scored as (

    select
        *,
        score >= {{ strong_threshold }}
            or (score >= {{ fuzzy_merge_threshold }} and same_first_word) as is_merge
    from fuzzy_candidates

),

resolved as (

    select
        ruled.source_system,
        ruled.raw_name,
        ruled.row_count,
        ruled.name_key,
        case
            when scored.is_merge then scored.candidate_key
            else ruled.rule_key
        end as final_key,
        case
            when scored.is_merge then 'fuzzy'
            else ruled.match_method
        end as match_method,
        iff(scored.is_merge, scored.score, null) as match_score,
        iff(not scored.is_merge and scored.score >= {{ review_threshold }},
            scored.candidate_key, null) as review_candidate_key,
        iff(not scored.is_merge and scored.score >= {{ review_threshold }},
            scored.score, null) as review_score
    from ruled
    left join scored
        on ruled.rule_key = scored.orphan_key

),

display_names as (

    -- display name per manufacturer: prefer the payments spelling, then recalls, then
    -- events, and within a source the most frequent name
    select
        final_key,
        raw_name as manufacturer_name
    from resolved
    qualify row_number() over (
        partition by final_key
        order by
            case source_system when 'payments' then 1 when 'recalls' then 2 else 3 end,
            row_count desc,
            raw_name
    ) = 1

)

select
    resolved.source_system,
    resolved.raw_name,
    resolved.row_count,
    resolved.name_key,
    md5(resolved.final_key) as manufacturer_key,
    resolved.final_key as manufacturer_match_key,
    display_names.manufacturer_name,
    resolved.match_method,
    resolved.match_score,
    resolved.review_candidate_key,
    resolved.review_score
from resolved
inner join display_names
    on resolved.final_key = display_names.final_key
