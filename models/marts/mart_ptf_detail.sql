{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'PTF_ID'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with fct_ptf as (
    select * from {{ ref('int_fct_ptf') }}
),

ptf as (
    select * from {{ ref('int_ptf') }}
),

xrt as (
    select * from {{ ref('int_fct_xrt') }}
)

select
    fct_ptf.dt_fct,
    fct_ptf.ptf_id,
    ptf.ptf_name,
    ptf.ptf_name_alt,
    ptf.client_id,
    ptf.currency,
    ptf.risk_profile,
    ptf.risk_profile_name,
    ptf.manager_id,
    ptf.manager_name,
    ptf.manager_group_id,
    ptf.manager_group_name,
    ptf.ext_manager_id,
    ptf.ext_manager_name,
    ptf.agent_id,
    ptf.agent_name,
    ptf.entity_id,
    ptf.entity_name,
    ptf.business_unit_id,
    ptf.business_unit_name,

    coalesce(xrt.rate_value, 1)                                              as xrt_rate,
    fct_ptf.pc_ptf,

    fct_ptf.mt_net,
    cast(fct_ptf.mt_net * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_net_ref,
    fct_ptf.mt_aci,
    cast(fct_ptf.mt_aci * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_aci_ref,
    fct_ptf.mt_lia,
    cast(fct_ptf.mt_lia * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_lia_ref,
    fct_ptf.mt_pnl,
    cast(fct_ptf.mt_pnl * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_pnl_ref,
    fct_ptf.mt_pnc,
    cast(fct_ptf.mt_pnc * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_pnc_ref,
    fct_ptf.mt_inc,
    cast(fct_ptf.mt_inc * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_inc_ref,
    fct_ptf.mt_out,
    cast(fct_ptf.mt_out * coalesce(xrt.rate_value, 1) as decimal(19,4))     as mt_out_ref,
    fct_ptf.mt_nnm_inc,
    cast(fct_ptf.mt_nnm_inc * coalesce(xrt.rate_value, 1) as decimal(19,4)) as mt_nnm_inc_ref,
    fct_ptf.mt_nnm_out,
    cast(fct_ptf.mt_nnm_out * coalesce(xrt.rate_value, 1) as decimal(19,4)) as mt_nnm_out_ref,
    fct_ptf.mt_int_inc,
    cast(fct_ptf.mt_int_inc * coalesce(xrt.rate_value, 1) as decimal(19,4)) as mt_int_inc_ref,
    fct_ptf.mt_int_out,
    cast(fct_ptf.mt_int_out * coalesce(xrt.rate_value, 1) as decimal(19,4)) as mt_int_out_ref,

    fct_ptf.loaded_at

from fct_ptf
inner join ptf
    on fct_ptf.ptf_id  = ptf.ptf_id
    and fct_ptf.dt_fct = ptf.dt_fct
left join xrt
    on ptf.currency = xrt.currency
    and xrt.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('int_fct_xrt') }} x2
        where x2.currency = ptf.currency
          and x2.dt_fct  <= fct_ptf.dt_fct
    )
order by fct_ptf.dt_fct desc, fct_ptf.ptf_id