with source as (
    select * from {{ ref('portfolio_snapshot') }}
),
calendar as (
    select * from {{ ref('stg_set_cal') }}
),
prf as (
    select * from {{ ref('stg_prf') }}
),
ccy as (
    select * from {{ ref('stg_ccy') }}
),
mng as (
    select * from {{ ref('stg_mng') }}
),
mng_grp as (
    select * from {{ ref('stg_mng_grp') }}
),
mng_ext as (
    select * from {{ ref('stg_mng_ext') }}
),
agn as (
    select * from {{ ref('stg_agn') }}
),
ent as (
    select * from {{ ref('stg_ent') }}
),
buu as (
    select * from {{ ref('stg_buu') }}
)

select
    cal.dt_fct,
    src.cd_ptf,
    src.lb_ptf,
    src.lb_ptf_alt,
    src.cd_cli,
    src.cd_ccy,
    coalesce(ccy.lb_ccy, src.cd_ccy)                        as lb_ccy,
    src.cd_prf,
    coalesce(prf.lb_prf, src.cd_prf)                        as lb_prf,
    src.cd_mng,
    coalesce(mng.lb_mng, src.cd_mng)                        as lb_mng,
    mng.cd_mng_grp,
    coalesce(mng_grp.lb_mng_grp, mng.cd_mng_grp)            as lb_mng_grp,
    src.cd_mng_ext,
    mng_ext.lb_mng_ext,
    src.cd_agn,
    agn.lb_agn,
    src.cd_ent,
    ent.lb_ent,
    src.cd_buu,
    buu.lb_buu,
    src.dt_cre,
    src.dt_clo,
    src.ts_stg,
    src.dbt_updated_at                                      as updated_at,
    src.dbt_valid_from                                      as valid_from,
    src.dbt_valid_to                                        as valid_to
from calendar cal
cross join source src
left join prf     on src.cd_prf      = prf.cd_prf
left join ccy     on src.cd_ccy      = ccy.cd_ccy
left join mng     on src.cd_mng      = mng.cd_mng
left join mng_grp on mng.cd_mng_grp  = mng_grp.cd_mng_grp
left join mng_ext on src.cd_mng_ext  = mng_ext.cd_mng_ext
left join agn     on src.cd_agn      = agn.cd_agn
left join ent     on src.cd_ent      = ent.cd_ent
left join buu     on src.cd_buu      = buu.cd_buu
where cal.dt_fct >= src.dt_cre
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)