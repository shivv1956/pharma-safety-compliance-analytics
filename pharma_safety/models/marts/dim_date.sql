-- Calendar dimension, one row per day, 2020-01-01 to 2030-12-31. `date_key` is YYYYMMDD.

with days as (

    select dateadd(day, seq4(), '2020-01-01'::date) as date_day
    from table(generator(rowcount => 4018))

)

select
    to_number(to_char(date_day, 'YYYYMMDD'))                    as date_key,
    date_day,
    year(date_day)                                              as year,
    quarter(date_day)                                           as quarter,
    month(date_day)                                             as month,
    monthname(date_day)                                         as month_name,
    date_trunc('month', date_day)::date                         as month_start,
    weekofyear(date_day)                                        as week_of_year,
    dayofweek(date_day)                                         as day_of_week,
    dayname(date_day)                                           as day_name,
    dayofweek(date_day) in (0, 6)                               as is_weekend
from days
where date_day <= '2030-12-31'
