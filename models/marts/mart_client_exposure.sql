{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CLIENT_ID'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

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
    cast(sum(ptf_idx.amount_position) as double) as amount_position,
    cast(sum(ptf_idx.amount_position * xrt_rates.rt_val) as double) as amount_position_base_ccy,
    cast({{ safe_divide('ptf_idx.amount_position', 'sum(ptf_idx.amount_position) over (partition by ptf_idx.client_id, ptf_idx.dt_fct)') }} as double) as weight_pct

from ptf_idx
inner join {{ ref('st0_fct_xrt') }} xrt_rates
    on ptf_idx.currency = xrt_rates.CD_CCY
    and xrt_rates.DT_FCT = (
        select max(x2.DT_FCT)
        from {{ ref('st0_fct_xrt') }} x2
        where x2.CD_CCY = ptf_idx.currency
          and x2.DT_FCT <= ptf_idx.dt_fct
    )

group by
    ptf_idx.dt_fct,
    ptf_idx.client_id,
    ptf_idx.asset_id,
    ptf_idx.currency,
    xrt_rates.rt_val,
    ptf_idx.amount_position