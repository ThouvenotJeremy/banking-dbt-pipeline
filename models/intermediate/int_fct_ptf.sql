{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ptf',
        on_schema_change='fail'
    )
}}

with fct_ptf as (
    select * from {{ ref('stg_fct_ptf') }}
    {% if is_incremental() %}
    where cd_fct_ptf not in (select cd_fct_ptf from {{ this }})
    {% endif %}
),

ptf as (
    select * from {{ ref('stg_ptf') }}
),

xrt as (
    select * from {{ ref('stg_fct_xrt') }}
)

select
    fct_ptf.id_stg_fct_ptf,
    fct_ptf.cd_fct_ptf,
    fct_ptf.cd_ptf,
    ptf.cd_cli,
    ptf.cd_ccy                                                      as cd_ccy_ptf,
    fct_ptf.dt_fct,
    fct_ptf.pc_ptf,

    -- Taux appliqué (devise du portefeuille → CHF à la date de fait)
    coalesce(xrt_ptf.rt_val, 1)                                     as xrt_rate,

    -- Montants natifs (devise du portefeuille) + conversion CHF
    fct_ptf.mt_net,
    cast(fct_ptf.mt_net * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_net_ref,
    fct_ptf.mt_aci,
    cast(fct_ptf.mt_aci * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_aci_ref,
    fct_ptf.mt_lia,
    cast(fct_ptf.mt_lia * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_lia_ref,
    fct_ptf.mt_pnl,
    cast(fct_ptf.mt_pnl * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_pnl_ref,
    fct_ptf.mt_pnc,
    cast(fct_ptf.mt_pnc * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_pnc_ref,

    -- Flux YTD natifs + CHF
    fct_ptf.mt_inc_ytd,
    cast(fct_ptf.mt_inc_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_inc_ref_ytd,
    fct_ptf.mt_out_ytd,
    cast(fct_ptf.mt_out_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_out_ref_ytd,
    fct_ptf.mt_nnm_inc_ytd,
    cast(fct_ptf.mt_nnm_inc_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_inc_ref_ytd,
    fct_ptf.mt_nnm_out_ytd,
    cast(fct_ptf.mt_nnm_out_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_out_ref_ytd,
    fct_ptf.mt_int_inc_ytd,
    cast(fct_ptf.mt_int_inc_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_inc_ref_ytd,
    fct_ptf.mt_int_out_ytd,
    cast(fct_ptf.mt_int_out_ytd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_out_ref_ytd,

    -- Flux MTD natifs + CHF
    fct_ptf.mt_inc_mtd,
    cast(fct_ptf.mt_inc_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_inc_ref_mtd,
    fct_ptf.mt_out_mtd,
    cast(fct_ptf.mt_out_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_out_ref_mtd,
    fct_ptf.mt_nnm_inc_mtd,
    cast(fct_ptf.mt_nnm_inc_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_inc_ref_mtd,
    fct_ptf.mt_nnm_out_mtd,
    cast(fct_ptf.mt_nnm_out_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_out_ref_mtd,
    fct_ptf.mt_int_inc_mtd,
    cast(fct_ptf.mt_int_inc_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_inc_ref_mtd,
    fct_ptf.mt_int_out_mtd,
    cast(fct_ptf.mt_int_out_mtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_out_ref_mtd,

    -- Flux DTD natifs + CHF
    fct_ptf.mt_inc_dtd,
    cast(fct_ptf.mt_inc_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_inc_ref_dtd,
    fct_ptf.mt_out_dtd,
    cast(fct_ptf.mt_out_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_out_ref_dtd,
    fct_ptf.mt_nnm_inc_dtd,
    cast(fct_ptf.mt_nnm_inc_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_inc_ref_dtd,
    fct_ptf.mt_nnm_out_dtd,
    cast(fct_ptf.mt_nnm_out_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_nnm_out_ref_dtd,
    fct_ptf.mt_int_inc_dtd,
    cast(fct_ptf.mt_int_inc_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_inc_ref_dtd,
    fct_ptf.mt_int_out_dtd,
    cast(fct_ptf.mt_int_out_dtd * coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_int_out_ref_dtd

from fct_ptf
inner join ptf
    on fct_ptf.cd_ptf = ptf.cd_ptf

-- XRT devise du portefeuille → CHF à la date de fait
left join xrt xrt_ptf
    on ptf.cd_ccy = xrt_ptf.cd_ccy
    and xrt_ptf.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('stg_fct_xrt') }} x2
        where x2.cd_ccy  = ptf.cd_ccy
          and x2.dt_fct <= fct_ptf.dt_fct
    )