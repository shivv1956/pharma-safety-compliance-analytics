-- Every distinct drug name seen in the three sources, with how often it appears and its
-- comparison key. One row per (source_system, raw_name).
--   payments        brand/product names 1-5 on each payment (blank slots skipped)
--   adverse_events  `medicinalproduct`, the name as the reporter typed it
--   recalls         openFDA brand name, else generic name, else the first phrase of the
--                   free-text product description

with payments as (

    {% for i in range(1, 6) %}
    select 'payments' as source_system, upper(product_name_{{ i }}) as raw_name, count(*) as row_count
    from {{ ref('stg_open_payments') }}
    where product_name_{{ i }} is not null
    group by 1, 2
    {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

events as (

    select 'adverse_events' as source_system, drug_name_upper as raw_name, count(*) as row_count
    from {{ ref('stg_adverse_event_drugs') }}
    where drug_name_upper is not null
    group by 1, 2

),

recalls as (

    select 'recalls' as source_system, raw_name, count(*) as row_count
    from {{ ref('int_recall_drug_names') }}
    where raw_name is not null
    group by 1, 2

),

unioned as (

    select * from payments
    union all
    select * from events
    union all
    select * from recalls

)

select
    source_system,
    raw_name,
    sum(row_count) as row_count,
    {{ normalize_drug_name('raw_name') }} as name_key
from unioned
where raw_name is not null
group by 1, 2
