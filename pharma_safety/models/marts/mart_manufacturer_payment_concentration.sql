-- How concentrated each manufacturer's physician payments are, per program year.
--   top_decile_share  share of the year's payments going to the top 10% of paid physicians
--   top10_share       share going to the 10 most-paid physicians
--   hhi               Herfindahl index of physician shares (0 = evenly spread, 1 = one physician)

with physician_totals as (

    select
        manufacturer_key,
        program_year,
        physician_key,
        sum(payment_amount_usd) as physician_usd
    from {{ ref('fct_payments') }}
    group by 1, 2, 3
    having sum(payment_amount_usd) > 0

),

ranked as (

    select
        *,
        row_number() over (partition by manufacturer_key, program_year order by physician_usd desc) as usd_rank,
        count(*) over (partition by manufacturer_key, program_year) as physicians_paid,
        sum(physician_usd) over (partition by manufacturer_key, program_year) as total_usd
    from physician_totals

)

select
    manufacturer_key,
    program_year,
    max(physicians_paid)                                              as physicians_paid,
    max(total_usd)                                                    as total_payments_usd,
    sum(iff(usd_rank <= ceil(physicians_paid * 0.1), physician_usd, 0)) / max(total_usd)
                                                                      as top_decile_share,
    sum(iff(usd_rank <= 10, physician_usd, 0)) / max(total_usd)       as top10_share,
    sum(power(physician_usd / total_usd, 2))                          as hhi
from ranked
group by 1, 2
