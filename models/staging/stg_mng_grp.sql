with st0_mng_grp as (
    select * from {{ source('st0', 'st0_mng_grp') }}
)

select
    cd_mng_grp      as manager_group_id,
    lb_mng_grp      as manager_group_name,
    cast(ts_stg as date) as loaded_at
from st0_mng_grp
