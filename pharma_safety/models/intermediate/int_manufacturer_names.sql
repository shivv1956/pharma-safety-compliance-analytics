-- Every distinct manufacturer / firm name seen in the three sources, with how often it
-- appears and its rule-based comparison key. One row per (source_system, raw_name).
-- Adverse-event names come from the openFDA drug lookup (172M rows), so this is a table.

with payments as (

    select
        'payments' as source_system,
        manufacturer_name as raw_name,
        count(*) as row_count
    from {{ ref('stg_open_payments') }}
    where manufacturer_name is not null
    group by 1, 2

),

recalls as (

    select
        'recalls' as source_system,
        recalling_firm as raw_name,
        count(*) as row_count
    from {{ ref('stg_recalls') }}
    where recalling_firm is not null
    group by 1, 2

),

events as (

    select
        'adverse_events' as source_system,
        trim(value) as raw_name,
        count(*) as row_count
    from {{ source('openfda', 'adverse_events__patient__drug__openfda__manufacturer_name') }}
    where nullif(trim(value), '') is not null
    group by 1, 2

),

unioned as (

    select * from payments
    union all
    select * from recalls
    union all
    select * from events

)

select
    source_system,
    raw_name,
    row_count,
    {{ normalize_firm_name('raw_name') }} as name_key
from unioned
