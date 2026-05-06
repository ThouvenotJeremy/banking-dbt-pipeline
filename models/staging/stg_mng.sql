with st0_mng as (
    select * from {{ source('st0', 'st0_mng') }}
)

select
cd_mng as manager_id,
lb_mng as manager_name,
cd_mng_grp as manager_group_id,
ts_stg as timestamp
from st0_mng