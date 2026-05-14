with st0_fct_xrt as (
    select * from {{ source('st0', 'st0_fct_xrt') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['cd_ccy', 'dt_fct']) }} as fct_xrt_id,
    cd_ccy              as currency,
    cast(dt_fct as date) as dt_fct,
    rt_fac              as rate_factor,
    rt_val              as rate_value,
    cast(ts_stg as date) as loaded_at
from st0_fct_xrt