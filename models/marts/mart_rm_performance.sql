{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'MANAGER_ID'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with aum_ytd as (
    select * from {{ ref('mart_aum_ytd') }}
),

-- Aggregation by RM (manager)
rm_daily_aum as (
    select
        dt_fct,
        manager_id,
        manager_name,
        sum(aum_current) as aum_current,
        sum(aum_ytd_start) as aum_ytd_start,
        count(distinct client_id) as client_count,
        count(distinct ptf_id) as portfolio_count,
        count(distinct client_category) as category_count,
        current_date as performance_date
    from aum_ytd
    group by
        dt_fct,
        manager_id,
        manager_name,
        current_date
),

-- YTD performance calculation
rm_performance as (
    select
        current.dt_fct,
        current.manager_id,
        current.manager_name,
        cast(current.aum_current as double) as aum_current,
        cast(current.aum_ytd_start as double) as aum_ytd_start,
        case
            when current.aum_ytd_start is null or current.aum_ytd_start = 0 then 0
            else ((current.aum_current - current.aum_ytd_start) / current.aum_ytd_start) * 100
        end as aum_ytd_variation_pct,
        cast(current.aum_current - coalesce(current.aum_ytd_start, 0) as double) as aum_ytd_variation_abs,
        current.client_count,
        current.portfolio_count,
        current.category_count,
        case
            when current.client_count > 0
            then cast(current.aum_current / current.client_count as double)
            else 0
        end as aum_avg_per_client,
        case
            when current.portfolio_count > 0
            then cast(current.aum_current / current.portfolio_count as double)
            else 0
        end as aum_avg_per_portfolio,
        current.performance_date,
        cast(current_timestamp as timestamp) as loaded_at
    from rm_daily_aum current
)

select
    dt_fct,
    manager_id,
    manager_name,
    aum_current,
    aum_ytd_start,
    aum_ytd_variation_pct,
    aum_ytd_variation_abs,
    client_count,
    portfolio_count,
    category_count,
    aum_avg_per_client,
    aum_avg_per_portfolio,
    performance_date,
    loaded_at
from rm_performance
{% if var("aum_year") is not none %}
where extract(year from dt_fct) = {{ var("aum_year") }}
{% endif %}
order by dt_fct desc, manager_id
