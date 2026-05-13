with st0_agn as (
    select * from {{ source('st0', 'st0_agn') }}
)

select
    cd_agn          as agent_id,
    lb_agn          as agent_name,
    cast(ts_stg as date) as loaded_at
from st0_agn
