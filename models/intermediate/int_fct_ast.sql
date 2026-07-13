{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ast',
        on_schema_change='fail'
    )
}}

with fct_ast as (
    select * from {{ ref('stg_fct_ast') }}
    {% if is_incremental() %}
    where cd_fct_ast not in (select cd_fct_ast from {{ this }})
    {% endif %}
),

ptf as (
    select * from {{ ref('stg_ptf') }}
),

xrt as (
    select * from {{ ref('stg_fct_xrt') }}
)

select
    fct_ast.id_stg_fct_ast,
    fct_ast.cd_fct_ast,
    fct_ast.cd_pos,
    fct_ast.cd_pos_typ,
    fct_ast.cd_ptf,
    ptf.cd_cli,
    fct_ast.dt_fct,
    fct_ast.cd_ccy,
    fct_ast.cd_ins,
    fct_ast.cd_ast,
    fct_ast.lb_fct_ast,
    fct_ast.qt_ast,

    -- Valorisation en devise de la position (source brute)
    fct_ast.mt_ast,
    fct_ast.mt_aci,
    fct_ast.mt_pnl,

    -- Taux appliqués
    coalesce(xrt_pos.rt_val, 1)                                     as xrt_rate_pos,
    coalesce(xrt_ptf.rt_val, 1)                                     as xrt_rate_ptf,

    -- Valorisation en devise du portefeuille (via pivot CHF)
    cast(fct_ast.mt_ast * coalesce(xrt_pos.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_ast_ptf,
    cast(fct_ast.mt_aci * coalesce(xrt_pos.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_aci_ptf,
    cast(fct_ast.mt_pnl * coalesce(xrt_pos.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_pnl_ptf,

    -- Valorisation en CHF (devise de référence banque)
    cast(fct_ast.mt_ast * coalesce(xrt_pos.rt_val, 1) as decimal(19,4)) as mt_ast_ref,
    cast(fct_ast.mt_aci * coalesce(xrt_pos.rt_val, 1) as decimal(19,4)) as mt_aci_ref,
    cast(fct_ast.mt_pnl * coalesce(xrt_pos.rt_val, 1) as decimal(19,4)) as mt_pnl_ref,

    -- Poids et performance
    fct_ast.rt_prm,
    fct_ast.rt_pam,
    fct_ast.pc_twr

from fct_ast
inner join ptf
    on fct_ast.cd_ptf = ptf.cd_ptf

-- XRT devise de la position → CHF
left join xrt xrt_pos
    on fct_ast.cd_ccy = xrt_pos.cd_ccy
    and xrt_pos.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('stg_fct_xrt') }} x2
        where x2.cd_ccy  = fct_ast.cd_ccy
          and x2.dt_fct <= fct_ast.dt_fct
    )

-- XRT devise du portefeuille → CHF (pivot pour _PTF)
left join xrt xrt_ptf
    on ptf.cd_ccy = xrt_ptf.cd_ccy
    and xrt_ptf.dt_fct = (
        select max(x3.dt_fct)
        from {{ ref('stg_fct_xrt') }} x3
        where x3.cd_ccy  = ptf.cd_ccy
          and x3.dt_fct <= fct_ast.dt_fct
    )