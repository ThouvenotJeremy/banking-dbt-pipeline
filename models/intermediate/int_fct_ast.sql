with ptf as (
    select * from {{ ref('stg_ptf') }}
),

fct_ast as (
    select * from {{ ref('stg_fct_ast') }}
)

select
    fct_ast.fct_ast_id,
    fct_ast.pos_id,
    fct_ast.pos_typ_id,
    fct_ast.ptf_id,
    ptf.client_id,
    fct_ast.asset_id,
    fct_ast.currency,
    fct_ast.quantity,
    fct_ast.amount          as amount_position,
    fct_ast.amount_ref      as amount_position_ref,
    fct_ast.amount_ptf      as amount_position_ptf,
    fct_ast.accrued_interest_ref,
    fct_ast.pnl_ref,
    fct_ast.net_change_ref,
    fct_ast.weight_ptf,
    fct_ast.value_date,
    fct_ast.loaded_at
from ptf
inner join fct_ast on ptf.ptf_id = fct_ast.ptf_id
