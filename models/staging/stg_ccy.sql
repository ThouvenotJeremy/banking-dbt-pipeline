with st0_ccy as (
    select * from {{ ref('st0_ccy') }}
)

select
    cd_ccy      as currency_id,
    lb_ccy      as currency_name,
    ts_stg      as loaded_at
from st0_ccy