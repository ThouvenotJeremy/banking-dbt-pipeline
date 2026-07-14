{% if target.type == 'duckdb' %}

    with months as (
        select unnest(generate_series(
            date_trunc('month', date '{{ var("start_date") }}'),
            date_trunc('month', current_date),
            interval '1 month'
        )) as month_start
    ),

    calendar as (
        select
            (month_start + interval '1 month' - interval '1 day')::date
                as dt_fct
        from months
        where month_start < date_trunc('month', current_date)
        union all
        select current_date as dt_fct
    )

{% else %}

with months as (
    select
        dateadd('month', seq4(), date_trunc('month', '{{ var("start_date") }}'::date)) as month_start
    from table(generator(rowcount => 100))
    where month_start <= date_trunc('month', current_date)
),
calendar as (
    select last_day(month_start) as dt_fct
    from months
    where month_start < date_trunc('month', current_date)
    union all
    select current_date as dt_fct
)

{% endif %}

select
    dt_fct,
    {% if target.type == 'duckdb' %}
        (strftime(dt_fct, '%Y%m%d'))::integer as vr_dwh_cal,
    {% else %}
    to_number(to_char(dt_fct, 'YYYYMMDD')) as vr_dwh_cal,
    {% endif %}
    1 as cd_cal
from calendar
order by dt_fct
