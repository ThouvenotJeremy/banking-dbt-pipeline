{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ope',
        on_schema_change='fail'
    )
}}

with fct_ope as (
    select * from {{ ref('stg_fct_ope') }}
    {% if is_incremental() %}
    where cd_fct_ope not in (select cd_fct_ope from {{ this }})
    {% endif %}
),

ptf as (
    select * from {{ ref('stg_ptf') }}
),

xrt as (
    select * from {{ ref('stg_fct_xrt') }}
)

select
    fct_ope.id_stg_fct_ope,
    fct_ope.cd_fct_ope,
    fct_ope.cd_ope,
    fct_ope.nb_seq_ptc,
    fct_ope.lb_fct_ope,
    fct_ope.cd_fct_ope_ext,
    fct_ope.cd_ope_typ,
    fct_ope.cd_deb_crd,
    fct_ope.yn_pro,
    fct_ope.cd_pos,
    fct_ope.cd_ptf,
    ptf.cd_cli,
    fct_ope.cd_ccy_ope,
    ptf.cd_ccy                                                      as cd_ccy_ptf,
    fct_ope.cd_ast,
    fct_ope.cd_ins,
    fct_ope.dt_cta,
    fct_ope.dt_exe,
    fct_ope.dt_val,
    fct_ope.qt_ope,

    -- Montants en devise de l'opération (source brute)
    fct_ope.mt_ope,
    fct_ope.mt_net,

    -- Taux appliqués (à la date comptable de l'opération)
    coalesce(xrt_ope.rt_val, 1)                                     as xrt_rate_ope,
    coalesce(xrt_ptf.rt_val, 1)                                     as xrt_rate_ptf,

    -- Montants en devise du portefeuille (via pivot CHF)
    cast(fct_ope.mt_ope * coalesce(xrt_ope.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_ope_ptf,
    cast(fct_ope.mt_net * coalesce(xrt_ope.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_net_ptf,

    -- Montants en CHF (devise de référence banque)
    cast(fct_ope.mt_ope * coalesce(xrt_ope.rt_val, 1) as decimal(19,4)) as mt_ope_ref,
    cast(fct_ope.mt_net * coalesce(xrt_ope.rt_val, 1) as decimal(19,4)) as mt_net_ref

from fct_ope
inner join ptf
    on fct_ope.cd_ptf = ptf.cd_ptf

-- XRT devise de l'opération → CHF à la date comptable
left join xrt xrt_ope
    on fct_ope.cd_ccy_ope = xrt_ope.cd_ccy
    and xrt_ope.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('stg_fct_xrt') }} x2
        where x2.cd_ccy  = fct_ope.cd_ccy_ope
          and x2.dt_fct <= fct_ope.dt_cta
    )

-- XRT devise du portefeuille → CHF à la date comptable (pivot pour _PTF)
left join xrt xrt_ptf
    on ptf.cd_ccy = xrt_ptf.cd_ccy
    and xrt_ptf.dt_fct = (
        select max(x3.dt_fct)
        from {{ ref('stg_fct_xrt') }} x3
        where x3.cd_ccy  = ptf.cd_ccy
          and x3.dt_fct <= fct_ope.dt_cta
    )