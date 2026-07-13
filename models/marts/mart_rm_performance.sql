{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CD_MNG'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with aum_ytd as (
    select * from {{ ref('mart_aum_ytd') }}
),

ptf as (
    select distinct cd_mng, cd_mng_grp, lb_mng_grp
    from {{ ref('int_ptf') }}
),

rm_daily_aum as (
    select
        aum.dt_fct,
        aum.cd_mng,
        aum.lb_mng,
        ptf.cd_mng_grp,
        ptf.lb_mng_grp,
        sum(aum.aum_current)                as aum_current,
        sum(aum.aum_ytd_start)              as aum_ytd_start,
        count(distinct aum.cd_cli)          as client_count,
        count(distinct aum.cd_ptf)          as portfolio_count,
        count(distinct aum.cd_cli_cat)      as category_count,
        current_date                        as performance_date
    from aum_ytd aum
    left join ptf on aum.cd_mng = ptf.cd_mng
    group by
        aum.dt_fct,
        aum.cd_mng,
        aum.lb_mng,
        ptf.cd_mng_grp,
        ptf.lb_mng_grp,
        current_date
),

rm_performance as (
    select
        current.dt_fct,
        current.cd_mng,
        current.lb_mng,
        current.cd_mng_grp,
        current.lb_mng_grp,
        cast(current.aum_current as double)     as aum_current,
        cast(current.aum_ytd_start as double)   as aum_ytd_start,
        case
            when current.aum_ytd_start is null or current.aum_ytd_start = 0 then 0
            else ((current.aum_current - current.aum_ytd_start) / current.aum_ytd_start) * 100
        end                                     as aum_ytd_variation_pct,
        cast(current.aum_current - coalesce(current.aum_ytd_start, 0) as double) as aum_ytd_variation_abs,
        current.client_count,
        current.portfolio_count,
        current.category_count,
        case
            when current.client_count > 0
            then cast(current.aum_current / current.client_count as double)
            else 0
        end                                     as aum_avg_per_client,
        case
            when current.portfolio_count > 0
            then cast(current.aum_current / current.portfolio_count as double)
            else 0
        end                                     as aum_avg_per_portfolio,
        current.performance_date,
        cast(current_timestamp as timestamp)    as loaded_at
    from rm_daily_aum current
)

select
    dt_fct,
    cd_mng,
    lb_mng,
    cd_mng_grp,
    lb_mng_grp,
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
order by dt_fct desc, cd_mng