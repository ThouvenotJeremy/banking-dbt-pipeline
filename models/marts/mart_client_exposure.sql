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

ins as (
    select * from {{ ref('stg_ins') }}
),

xrt as (
    select * from {{ ref('st0_fct_xrt') }}
)

select
    ptf_idx.dt_fct,
    ptf_idx.client_id,
    cli.client_name,
    cli.client_category,
    cli.client_category_name,
    cli.country,
    cli.country_name,
    ptf_idx.ptf_id,
    ptf.ptf_name,
    ptf.manager_id,
    ptf.manager_name,
    ptf_idx.risk_profile,
    ptf.risk_profile_name,
    ptf_idx.asset_id,
    ins.ins_name                                        as asset_name,
    ins.ins_grp_id                                      as asset_class,
    ptf_idx.currency,
    xrt.rt_val                                          as xrt_rate,
    cast(ptf_idx.amount_position as double)             as amount_position,
    cast(ptf_idx.amount_position * coalesce(xrt.rt_val, 1) as double) as amount_position_base_ccy,
    cast(
        {{ safe_divide(
            'ptf_idx.amount_position',
            'sum(ptf_idx.amount_position) over (partition by ptf_idx.client_id, ptf_idx.dt_fct)'
        ) }}
    as double)                                          as weight_pct

from ptf_idx
left join cli
    on ptf_idx.client_id = cli.client_id
    and ptf_idx.dt_fct   = cli.dt_fct
left join ptf
    on ptf_idx.ptf_id  = ptf.ptf_id
    and ptf_idx.dt_fct = ptf.dt_fct
left join ins
    on ptf_idx.asset_id = ins.ins_id
left join xrt
    on ptf_idx.currency = xrt.cd_ccy
    and xrt.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('st0_fct_xrt') }} x2
        where x2.cd_ccy    = ptf_idx.currency
          and x2.dt_fct   <= ptf_idx.dt_fct
    )