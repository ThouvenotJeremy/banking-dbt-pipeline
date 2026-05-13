with st0_cty as (
    select * from {{ ref('st0_cty') }}
)

select
    cd_cty      as country_id,
    lb_cty      as country_name,
    ts_stg      as loaded_at
from st0_cty