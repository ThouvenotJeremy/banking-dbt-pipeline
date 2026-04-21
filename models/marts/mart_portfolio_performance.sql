with fct_ast as (
    select * from {{ ref('int_fct_ast') }}
),

xrt_prices as (
    select * from {{ ref('st0_fct_xrt_prices') }}
),

xrt_rates as (
    select * from {{ ref('st0_fct_xrt') }}
)


select
    fct_ast.ptf_id,
    fct_ast.client_id,
    fct_ast.asset_id,
    fct_ast.currency,
    fct_ast.amount_position,
    xrt_prices.mt_price as asset_price,
    xrt_prices.cd_ccy as asset_price_currency,
    xrt_rates.rt_val as xrt_rate,
    xrt_rates.cd_ccy as xrt_rate_currency,
    fct_ast.amount_position * xrt_prices.mt_price as market_value,
    (fct_ast.amount_position * xrt_prices.mt_price)
    * xrt_rates.rt_val as market_value_usd,
    current_date as performance_date,
    current_timestamp as loaded_at
from fct_ast
left join xrt_prices
    on
        fct_ast.asset_id = xrt_prices.cd_ast
        and fct_ast.currency = xrt_prices.cd_ccy
left join xrt_rates
    on fct_ast.currency = xrt_rates.cd_ccy
