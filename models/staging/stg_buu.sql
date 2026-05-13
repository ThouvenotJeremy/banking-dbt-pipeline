with st0_buu as (
    select * from {{ source('st0', 'st0_buu') }}
)

select
    cd_buu          as business_unit_id,
    lb_buu          as business_unit_name,
    cast(ts_stg as date) as loaded_at
from st0_buu
