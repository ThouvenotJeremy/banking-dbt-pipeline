{{
    config(
        materialized='incremental',
        unique_key='cd_fct_mvt',
        on_schema_change='fail'
    )
}}

with fct_mvt as (
    select * from {{ ref('stg_fct_mvt') }}
    {% if is_incremental() %}
    where cd_fct_mvt not in (select cd_fct_mvt from {{ this }})
    {% endif %}
),

ptf as (
    select * from {{ ref('stg_ptf') }}
),

xrt as (
    select * from {{ ref('stg_fct_xrt') }}
)

select
    fct_mvt.id_stg_fct_mvt,
    fct_mvt.cd_fct_mvt,
    fct_mvt.cd_pos,
    fct_mvt.cd_fct_ope,
    fct_mvt.yn_ext,
    fct_mvt.dt_cta,
    fct_mvt.id_obj_mvt_cat,
    fct_mvt.cd_mvt_typ,
    fct_mvt.cd_ptf,
    ptf.cd_cli,
    fct_mvt.cd_mvt_res,
    fct_mvt.cd_ast,
    fct_mvt.cd_ins,
    fct_mvt.cd_ccy_mvt,
    ptf.cd_ccy                                                      as cd_ccy_ptf,

    -- Montant en devise du mouvement (source brute)
    fct_mvt.mt_mvt,

    -- Taux appliqués (à la date comptable)
    coalesce(xrt_mvt.rt_val, 1)                                     as xrt_rate_mvt,
    coalesce(xrt_ptf.rt_val, 1)                                     as xrt_rate_ptf,

    -- Montant en devise du portefeuille (via pivot CHF)
    cast(fct_mvt.mt_mvt * coalesce(xrt_mvt.rt_val, 1)
         / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4))            as mt_mvt_ptf,

    -- Montant en CHF (devise de référence banque)
    cast(fct_mvt.mt_mvt * coalesce(xrt_mvt.rt_val, 1) as decimal(19,4)) as mt_mvt_ref

from fct_mvt
inner join ptf
    on fct_mvt.cd_ptf = ptf.cd_ptf

-- XRT devise du mouvement → CHF à la date comptable
left join xrt xrt_mvt
    on fct_mvt.cd_ccy_mvt = xrt_mvt.cd_ccy
    and xrt_mvt.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('stg_fct_xrt') }} x2
        where x2.cd_ccy  = fct_mvt.cd_ccy_mvt
          and x2.dt_fct <= fct_mvt.dt_cta
    )

-- XRT devise du portefeuille → CHF à la date comptable (pivot pour _PTF)
left join xrt xrt_ptf
    on ptf.cd_ccy = xrt_ptf.cd_ccy
    and xrt_ptf.dt_fct = (
        select max(x3.dt_fct)
        from {{ ref('stg_fct_xrt') }} x3
        where x3.cd_ccy  = ptf.cd_ccy
          and x3.dt_fct <= fct_mvt.dt_cta
    )