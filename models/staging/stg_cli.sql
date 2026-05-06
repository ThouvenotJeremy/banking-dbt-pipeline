with st0_cli as (
    select * from {{ source('st0', 'st0_cli') }}
)

select
    cd_cli as client_id,
    lb_cli as client_name,
    cd_cli_cat as client_category,
    cd_ccy as currency,
    cd_cty_dom as country,
    cd_mng_rel as relationship_manager_id,
    cast(dt_cre as date) as opening_date,
    dt_clo as closing_date,
    cast(ts_stg as timestamp) as loaded_at
from st0_cli
