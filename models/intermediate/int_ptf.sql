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
    src.ptf_id,
    src.ptf_name,
    src.ptf_name_alt,
    src.client_id,
    src.currency,
    coalesce(ccy.currency_name, src.currency)               as currency_name,
    src.risk_profile,
    coalesce(prf.risk_profile_name, src.risk_profile)       as risk_profile_name,
    src.manager_id,
    coalesce(mng.manager_name, src.manager_id)              as manager_name,
    mng.manager_group_id,
    coalesce(mng_grp.manager_group_name, mng.manager_group_id) as manager_group_name,
    src.ext_manager_id,
    mng_ext.ext_manager_name,
    src.agent_id,
    agn.agent_name,
    src.entity_id,
    ent.entity_name,
    src.business_unit_id,
    buu.business_unit_name,
    src.loaded_at,
    src.dbt_updated_at                                      as updated_at,
    src.dbt_valid_from                                      as valid_from,
    src.dbt_valid_to                                        as valid_to
from calendar cal
cross join source src
left join prf     on src.risk_profile    = prf.risk_profile_id
left join ccy     on src.currency        = ccy.currency_id
left join mng     on src.manager_id      = mng.manager_id
left join mng_grp on mng.manager_group_id = mng_grp.manager_group_id
left join mng_ext on src.ext_manager_id  = mng_ext.ext_manager_id
left join agn     on src.agent_id        = agn.agent_id
left join ent     on src.entity_id       = ent.entity_id
left join buu     on src.business_unit_id = buu.business_unit_id
where cal.dt_fct >= src.opening_date
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)