with stg_fct_xrt as (
    select * from {{ ref('stg_fct_xrt') }}
)

select
    fct_xrt_id,
    currency,
    dt_fct,
    rate_factor,
    rate_value,
    loaded_at
from stg_fct_xrt