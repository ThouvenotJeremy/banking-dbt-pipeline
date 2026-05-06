with st0_ins as (
    select * from {{ source('st0', 'st0_ins') }}
)

select
    cd_ins as ins_id,
    lb_ins as ins_name,
    cd_ins_grp as ins_grp_id,
    cast(ts_stg as date) as loaded_at
from st0_ins
