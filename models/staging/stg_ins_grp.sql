with st0_ins_grp as (
    select * from {{ source('st0', 'st0_ins_grp') }}
)

select
    cd_ins_grp      as ins_grp_id,
    lb_ins_grp      as ins_grp_name,
    cast(ts_stg as date) as loaded_at
from st0_ins_grp
