with ptf_idx as (
    select * from {{ ref('int_ptf_idx') }}
),

xrt_rates as (
    select * from {{ ref('st0_fct_xrt') }}
)

select
    ptf_idx.dt_fct,
    ptf_idx.client_id,
    ptf_idx.asset_id,
    ptf_idx.currency,
    xrt_rates.rt_val as xrt_rate,
    sum(ptf_idx.amount_position) as amount_position,
    sum(ptf_idx.amount_position * xrt_rates.rt_val) as amount_position_base_ccy

from ptf_idx
asof join xrt_rates
    on ptf_idx.pos_currency = xrt_rates.cd_ccy
    and ptf_idx.dt_fct >= cast(xrt_rates.ts_stg as date)

group by
    ptf_idx.dt_fct,
    ptf_idx.client_id,
    ptf_idx.asset_id,
    ptf_idx.currency,
    xrt_rates.rt_val