with months as (
    select
        dateadd('month', seq4(), date_trunc('month', '2024-01-01'::date)) as month_start
    from table(generator(rowcount => 100))
    where month_start <= date_trunc('month', current_date)
),

calendar as (
    select
        last_day(month_start) as dt_fct
    from months
    where month_start < date_trunc('month', current_date)

    union all

    select current_date as dt_fct
)

select
    dt_fct,
    to_number(to_char(dt_fct, 'YYYYMMDD')) as vr_dwh_cal,
    1 as cd_cal
from calendar
order by dt_fct