-- Reporting table for Power BI: one row per manufacturer and month with payments,
-- suspect-drug adverse-event reports and recalls side by side.
-- Months with no activity in any source have no row.

with payments as (

    select
        manufacturer_key,
        date_trunc('month', payment_date)::date as month_start,
        count(*) as payment_count,
        sum(payment_amount_usd) as payment_usd,
        count(distinct physician_key) as physicians_paid
    from {{ ref('fct_payments') }}
    group by 1, 2

),

events as (

    select
        manufacturer_key,
        date_trunc('month', received_date)::date as month_start,
        count(distinct adverse_event_report_id) as suspect_reports,
        count(distinct iff(is_serious, adverse_event_report_id, null)) as serious_reports,
        count(distinct iff(is_death, adverse_event_report_id, null)) as death_reports,
        count(distinct iff(is_hospitalization, adverse_event_report_id, null)) as hospitalization_reports
    from {{ ref('fct_adverse_events') }}
    where is_suspect and manufacturer_key is not null
    group by 1, 2

),

recalls as (

    select
        manufacturer_key,
        date_trunc('month', report_date)::date as month_start,
        count(*) as recalls,
        count_if(is_class_i) as class_i_recalls
    from {{ ref('fct_recalls') }}
    group by 1, 2

),

spine as (

    select manufacturer_key, month_start from payments
    union
    select manufacturer_key, month_start from events
    union
    select manufacturer_key, month_start from recalls

)

select
    spine.manufacturer_key,
    manufacturers.manufacturer_name,
    spine.month_start,
    coalesce(payments.payment_count, 0)            as payment_count,
    coalesce(payments.payment_usd, 0)              as payment_usd,
    coalesce(payments.physicians_paid, 0)          as physicians_paid,
    coalesce(events.suspect_reports, 0)            as suspect_reports,
    coalesce(events.serious_reports, 0)            as serious_reports,
    coalesce(events.death_reports, 0)              as death_reports,
    coalesce(events.hospitalization_reports, 0)    as hospitalization_reports,
    coalesce(recalls.recalls, 0)                   as recalls,
    coalesce(recalls.class_i_recalls, 0)           as class_i_recalls
from spine
inner join {{ ref('dim_manufacturers') }} as manufacturers
    on manufacturers.manufacturer_key = spine.manufacturer_key
left join payments
    on payments.manufacturer_key = spine.manufacturer_key and payments.month_start = spine.month_start
left join events
    on events.manufacturer_key = spine.manufacturer_key and events.month_start = spine.month_start
left join recalls
    on recalls.manufacturer_key = spine.manufacturer_key and recalls.month_start = spine.month_start
