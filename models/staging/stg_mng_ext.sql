with st0_mng_ext as (
    select * from {{ source('st0', 'st0_mng_ext') }}
)

select
    cd_mng_ext      as ext_manager_id,
    lb_mng_ext      as ext_manager_name,
    cast(ts_stg as date) as loaded_at
from st0_mng_ext
