with source as (
    select * from {{ ref('portfolio_snapshot') }}
),
calendar as (
    select * from {{ ref('stg_set_cal') }}
)

select
    dt_fct,
    ptf_id,
    ptf_name,
    client_id,
    currency,
    risk_profile,
    loaded_at,
    dbt_updated_at as updated_at,
    dbt_valid_from as valid_from,
    dbt_valid_to as valid_to
from calendar
cross join source
where calendar.dt_fct >= source.opening_date
  and calendar.dt_fct >= cast(source.dbt_valid_from as date)
  and (cast(source.dbt_valid_to as date) > calendar.dt_fct
       or source.dbt_valid_to is null)