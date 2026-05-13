with st0_ent as (
    select * from {{ source('st0', 'st0_ent') }}
)

select
    cd_ent          as entity_id,
    lb_ent          as entity_name,
    cast(ts_stg as date) as loaded_at
from st0_ent
