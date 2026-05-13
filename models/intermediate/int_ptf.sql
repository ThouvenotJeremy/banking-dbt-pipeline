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
)

select
    cal.dt_fct,
    src.ptf_id,
    src.ptf_name,
    src.client_id,
    src.currency,
    coalesce(ccy.currency_name, src.currency)           as currency_name,
    src.risk_profile,
    coalesce(prf.risk_profile_name, src.risk_profile)   as risk_profile_name,
    src.manager_id,
    coalesce(mng.manager_name, src.manager_id)          as manager_name,
    mng.manager_group_id,
    src.loaded_at,
    src.dbt_updated_at                                  as updated_at,
    src.dbt_valid_from                                  as valid_from,
    src.dbt_valid_to                                    as valid_to
from calendar cal
cross join source src
left join prf on src.risk_profile = prf.risk_profile_id
left join ccy on src.currency     = ccy.currency_id
left join mng on src.manager_id   = mng.manager_id
where cal.dt_fct >= src.opening_date
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)