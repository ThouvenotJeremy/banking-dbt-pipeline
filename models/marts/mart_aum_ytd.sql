{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CLIENT_ID'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with ptf_idx as (
    select * from {{ ref('int_ptf_idx') }}
),

cli as (
    select * from {{ ref('int_cli') }}
),

ptf as (
    select * from {{ ref('int_ptf') }}
),

-- Daily AUM aggregation with forward-filled positions
daily_aum as (
    select
        ptf_idx.dt_fct,
        ptf_idx.client_id,
        ptf_idx.ptf_id,
        ptf.ptf_name,
        cli.client_name,
        cli.client_category,
        cli.currency as client_currency,
        sum(ptf_idx.amount_position) as aum,
        current_date as performance_date,
        current_timestamp as loaded_at
    from ptf_idx
    inner join ptf on ptf_idx.ptf_id = ptf.ptf_id
        and ptf_idx.client_id = ptf.client_id
        and ptf_idx.dt_fct = ptf.dt_fct
    inner join cli on ptf_idx.client_id = cli.client_id
        and cli.dt_fct = ptf_idx.dt_fct
    group by
        ptf_idx.dt_fct,
        ptf_idx.client_id,
        ptf_idx.ptf_id,
        ptf.ptf_name,
        cli.client_name,
        cli.client_category,
        cli.currency,
        current_date,
        current_timestamp
),

-- YTD calculation
ytd_calculation as (
    select
        current_aum.dt_fct,
        current_aum.client_id,
        current_aum.ptf_id,
        current_aum.ptf_name,
        current_aum.client_name,
        current_aum.client_category,
        current_aum.client_currency,
        current_aum.aum as aum_current,
        ytd_start.aum as aum_ytd_start,
        case
            when ytd_start.aum is null or ytd_start.aum = 0 then 0
            else ((current_aum.aum - ytd_start.aum) / ytd_start.aum) * 100
        end as aum_ytd_variation_pct,
        current_aum.aum - coalesce(ytd_start.aum, 0) as aum_ytd_variation_abs,
        current_aum.performance_date,
        current_aum.loaded_at
    from daily_aum current_aum
    left join daily_aum ytd_start
        on current_aum.client_id = ytd_start.client_id
        and current_aum.ptf_id = ytd_start.ptf_id
        and ytd_start.dt_fct = (
            select min(dt_fct)
            from {{ ref('stg_set_cal') }}
            where extract(year from dt_fct) = extract(year from current_aum.dt_fct)
        )
)

select
    dt_fct,
    client_id,
    ptf_id,
    ptf_name,
    client_name,
    client_category,
    client_currency,
    aum_current,
    aum_ytd_start,
    aum_ytd_variation_pct,
    aum_ytd_variation_abs,
    performance_date,
    loaded_at
from ytd_calculation
{% if var("aum_year") is not none %}
where extract(year from dt_fct) = {{ var("aum_year") }}
{% endif %}
order by dt_fct desc, client_id, ptf_id
