with st0_prf as (
    select * from {{ ref('st0_prf') }}
)

select
    cd_prf      as risk_profile_id,
    lb_prf      as risk_profile_name,
    ts_stg      as loaded_at
from st0_prf