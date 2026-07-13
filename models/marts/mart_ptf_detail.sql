{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CD_PTF'],
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
)

select
    fct_ptf.dt_fct,
    fct_ptf.cd_ptf,
    ptf.lb_ptf,
    ptf.lb_ptf_alt,
    fct_ptf.cd_cli,
    fct_ptf.cd_ccy_ptf,
    ptf.lb_ccy,
    ptf.cd_prf,
    ptf.lb_prf,
    ptf.cd_mng,
    ptf.lb_mng,
    ptf.cd_mng_grp,
    ptf.lb_mng_grp,
    ptf.cd_mng_ext,
    ptf.lb_mng_ext,
    ptf.cd_agn,
    ptf.lb_agn,
    ptf.cd_ent,
    ptf.lb_ent,
    ptf.cd_buu,
    ptf.lb_buu,

    fct_ptf.xrt_rate,
    fct_ptf.pc_ptf,

    fct_ptf.mt_net,
    fct_ptf.mt_net_ref,
    fct_ptf.mt_aci,
    fct_ptf.mt_aci_ref,
    fct_ptf.mt_lia,
    fct_ptf.mt_lia_ref,
    fct_ptf.mt_pnl,
    fct_ptf.mt_pnl_ref,
    fct_ptf.mt_pnc,
    fct_ptf.mt_pnc_ref,

    fct_ptf.mt_inc_ytd,
    fct_ptf.mt_inc_ref_ytd,
    fct_ptf.mt_out_ytd,
    fct_ptf.mt_out_ref_ytd,
    fct_ptf.mt_nnm_inc_ytd,
    fct_ptf.mt_nnm_inc_ref_ytd,
    fct_ptf.mt_nnm_out_ytd,
    fct_ptf.mt_nnm_out_ref_ytd,
    fct_ptf.mt_int_inc_ytd,
    fct_ptf.mt_int_inc_ref_ytd,
    fct_ptf.mt_int_out_ytd,
    fct_ptf.mt_int_out_ref_ytd,

    fct_ptf.mt_inc_mtd,
    fct_ptf.mt_inc_ref_mtd,
    fct_ptf.mt_out_mtd,
    fct_ptf.mt_out_ref_mtd,
    fct_ptf.mt_nnm_inc_mtd,
    fct_ptf.mt_nnm_inc_ref_mtd,
    fct_ptf.mt_nnm_out_mtd,
    fct_ptf.mt_nnm_out_ref_mtd,
    fct_ptf.mt_int_inc_mtd,
    fct_ptf.mt_int_inc_ref_mtd,
    fct_ptf.mt_int_out_mtd,
    fct_ptf.mt_int_out_ref_mtd,

    fct_ptf.mt_inc_dtd,
    fct_ptf.mt_inc_ref_dtd,
    fct_ptf.mt_out_dtd,
    fct_ptf.mt_out_ref_dtd,
    fct_ptf.mt_nnm_inc_dtd,
    fct_ptf.mt_nnm_inc_ref_dtd,
    fct_ptf.mt_nnm_out_dtd,
    fct_ptf.mt_nnm_out_ref_dtd,
    fct_ptf.mt_int_inc_dtd,
    fct_ptf.mt_int_inc_ref_dtd,
    fct_ptf.mt_int_out_dtd,
    fct_ptf.mt_int_out_ref_dtd

from fct_ptf
inner join ptf
    on fct_ptf.cd_ptf  = ptf.cd_ptf
    and fct_ptf.dt_fct = ptf.dt_fct
order by fct_ptf.dt_fct desc, fct_ptf.cd_ptf