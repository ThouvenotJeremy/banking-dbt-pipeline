with source as (
    select * from {{ ref('clients_snapshot') }}
),
calendar as (
    select * from {{ ref('stg_set_cal') }}
),
cty as (
    select * from {{ ref('stg_cty') }}
),
cli_cat as (
    select * from {{ ref('stg_cli_cat') }}
),
mng as (
    select * from {{ ref('stg_mng') }}
)

select
    cal.dt_fct,
    src.cd_cli,
    src.lb_cli,
    src.lb_cli_alt,
    src.cd_cli_cat,
    coalesce(cli_cat.lb_cli_cat, src.cd_cli_cat)            as lb_cli_cat,
    src.cd_ccy,
    src.cd_cty_dom,
    coalesce(cty.lb_cty, src.cd_cty_dom)                    as lb_cty_dom,
    src.cd_cty_nat,
    src.cd_mng_rel,
    coalesce(mng.lb_mng, src.cd_mng_rel)                    as lb_mng_rel,
    src.dt_cre,
    src.dt_clo,
    src.ts_stg,
    src.dbt_updated_at                                      as updated_at,
    src.dbt_valid_from                                      as valid_from,
    src.dbt_valid_to                                        as valid_to
from calendar cal
cross join source src
left join cty     on src.cd_cty_dom  = cty.cd_cty
left join cli_cat on src.cd_cli_cat  = cli_cat.cd_cli_cat
left join mng     on src.cd_mng_rel  = mng.cd_mng
where cal.dt_fct >= src.dt_cre
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)