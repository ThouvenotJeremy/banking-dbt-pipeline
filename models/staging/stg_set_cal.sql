with months as (
    select unnest(generate_series(
        date_trunc('month', date '2024-01-01'),
        date_trunc('month', current_date),
        interval '1 month'
    )) as month_start
),

calendar as (
    select
        (month_start + interval '1 month' - interval '1 day')::date as dt_fct
    from months
    where month_start < date_trunc('month', current_date)

    union all

    select current_date as dt_fct
)

select
    dt_fct,
    cast(strftime(dt_fct, '%Y%m%d') as integer) as vr_dwh_cal,
    1                                            as cd_cal
from calendar
order by dt_fct