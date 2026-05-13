with st0_cli_cat as (
    select * from {{ ref('st0_cli_cat') }}
)

select
    cd_cli_cat  as client_category_id,
    lb_cli_cat  as client_category_name,
    ts_stg      as loaded_at
from st0_cli_cat