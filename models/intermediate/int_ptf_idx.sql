with ptf as (
    select * from {{ ref('int_dim_ptf') }}
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
    fct_ast.currency as pos_currency
from ptf
asof join fct_ast
    on ptf.ptf_id = fct_ast.ptf_id
    and ptf.client_id = fct_ast.client_id
    and ptf.dt_fct >= fct_ast.value_date