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
)

select
    cal.dt_fct,
    src.client_id,
    src.client_name,
    src.client_category,
    coalesce(cli_cat.client_category_name, src.client_category) as client_category_name,
    src.currency,
    src.country,
    coalesce(cty.country_name, src.country)                 as country_name,
    src.nationality,
    src.relationship_manager_id,
    src.opening_date,
    src.closing_date,
    src.loaded_at,
    src.dbt_updated_at                                      as updated_at,
    src.dbt_valid_from                                      as valid_from,
    src.dbt_valid_to                                        as valid_to
from calendar cal
cross join source src
left join cty     on src.country         = cty.country_id
left join cli_cat on src.client_category = cli_cat.client_category_id
where cal.dt_fct >= src.opening_date
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)