with calendar as (
    select * from {{ ref('stg_set_cal') }}
    where dt_fct >= '{{ var("start_date") }}'
),
ptf as (
    select * from {{ ref('int_ptf') }}
    where dt_fct >= '{{ var("start_date") }}'
),
fct_ast as (
    select * from {{ ref('int_fct_ast') }}
)

select
    ptf.dt_fct,
    ptf.ptf_id,
    ptf.client_id,
    ptf.currency,
    ptf.risk_profile,
    fct_ast.asset_id,
    fct_ast.quantity,
    fct_ast.amount_position,
    fct_ast.amount_position_ref,
    fct_ast.pnl_ref,
    fct_ast.weight_ptf,
    fct_ast.currency        as pos_currency
from calendar
inner join ptf on calendar.dt_fct = ptf.dt_fct
inner join fct_ast
    on ptf.ptf_id = fct_ast.ptf_id
    and ptf.client_id = fct_ast.client_id
    and fct_ast.value_date = (
        select max(f2.value_date)
        from {{ ref('int_fct_ast') }} f2
        where f2.ptf_id = ptf.ptf_id
          and f2.value_date <= ptf.dt_fct
    )
