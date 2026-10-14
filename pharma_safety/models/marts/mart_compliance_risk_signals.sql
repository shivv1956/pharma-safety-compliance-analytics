-- The rules behind the compliance agent: one row per manufacturer that paid physicians in
-- `analysis_year`, with the four signals and whether all of them fire together.
--
--   is_material_payer           total payments >= min_payments_usd
--   high_payment_concentration  top-decile payment share (share going to the top 10% of paid
--                               physicians) is in the top quartile among material payers.
--                               It is relative because the share is high for everyone
--                               (median ~0.9), so an absolute bar would flag all manufacturers.
--   rising_serious_events       serious suspect-drug reports in H2 >= rising_ratio x H1,
--                               and at least min_h2_serious_reports in H2
--   has_class_i_recall          at least one Class I recall reported in the year
--
-- alert_level: 'critical' when all four signals fire, 'watch' when three do, else null.
-- Both are flagged for the compliance agent to review.
--
-- Thresholds are dbt vars (dbt_project.yml). Events and recalls are matched to the payment
-- year by calendar year. FAERS lags real time, so late-year event counts can be incomplete.

{% set year = var('analysis_year') %}

with payments as (

    select * from {{ ref('mart_manufacturer_payment_concentration') }}
    where program_year = {{ year }}

),

events as (

    select
        manufacturer_key,
        count(distinct adverse_event_report_id) as suspect_reports,
        count(distinct iff(is_serious, adverse_event_report_id, null)) as serious_reports,
        count(distinct iff(is_serious and month(received_date) <= 6, adverse_event_report_id, null)) as serious_reports_h1,
        count(distinct iff(is_serious and month(received_date) > 6, adverse_event_report_id, null)) as serious_reports_h2
    from {{ ref('fct_adverse_events') }}
    where is_suspect
        and manufacturer_key is not null
        and year(received_date) = {{ year }}
    group by 1

),

recalls as (

    select
        manufacturer_key,
        count(*) as recalls,
        count_if(is_class_i) as class_i_recalls,
        max(iff(is_class_i, report_date, null)) as latest_class_i_recall_date
    from {{ ref('fct_recalls') }}
    where year(report_date) = {{ year }}
    group by 1

),

concentration_cutoff as (

    select
        percentile_cont({{ var('concentration_percentile') }}) within group (order by top_decile_share) as cutoff
    from payments
    where total_payments_usd >= {{ var('min_payments_usd') }}

),

signals as (

    select
        payments.manufacturer_key,
        manufacturers.manufacturer_name,
        payments.program_year,
        payments.total_payments_usd,
        payments.physicians_paid,
        payments.top_decile_share,
        payments.top10_share,
        payments.hhi,
        coalesce(events.suspect_reports, 0) as suspect_reports,
        coalesce(events.serious_reports, 0) as serious_reports,
        coalesce(events.serious_reports_h1, 0) as serious_reports_h1,
        coalesce(events.serious_reports_h2, 0) as serious_reports_h2,
        coalesce(recalls.recalls, 0) as recalls,
        coalesce(recalls.class_i_recalls, 0) as class_i_recalls,
        recalls.latest_class_i_recall_date,

        payments.top_decile_share >= concentration_cutoff.cutoff as high_payment_concentration,
        payments.total_payments_usd >= {{ var('min_payments_usd') }} as is_material_payer,
        coalesce(events.serious_reports_h2, 0) >= {{ var('min_h2_serious_reports') }}
            and coalesce(events.serious_reports_h2, 0) >= {{ var('rising_ratio') }} * coalesce(events.serious_reports_h1, 0)
            as rising_serious_events,
        coalesce(recalls.class_i_recalls, 0) > 0 as has_class_i_recall
    from payments
    inner join {{ ref('dim_manufacturers') }} as manufacturers
        on manufacturers.manufacturer_key = payments.manufacturer_key
    cross join concentration_cutoff
    left join events
        on events.manufacturer_key = payments.manufacturer_key
    left join recalls
        on recalls.manufacturer_key = payments.manufacturer_key

)

select
    *,
    high_payment_concentration::int + is_material_payer::int + rising_serious_events::int + has_class_i_recall::int
        as signals_met,
    case
        when high_payment_concentration and is_material_payer and rising_serious_events and has_class_i_recall
            then 'critical'
        when high_payment_concentration::int + is_material_payer::int + rising_serious_events::int + has_class_i_recall::int = 3
            then 'watch'
    end as alert_level,
    alert_level is not null as is_flagged
from signals
