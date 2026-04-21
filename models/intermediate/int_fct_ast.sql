with ptf as (
    select * from {{ ref('stg_dim_ptf') }}
),

fct_ast as (
    select * from {{ ref('stg_fct_ast') }}
)

select
    fct_ast.fct_ast_id as fct_ast_id,
    fct_ast.pos_id as pos_id,
    fct_ast.pos_typ_id as pos_typ_id,
    fct_ast.ptf_id as ptf_id,
    ptf.client_id as client_id,
    fct_ast.asset_id as asset_id,
    fct_ast.currency as currency,
    fct_ast.quantity as quantity,
    fct_ast.amount as amount_position,
    fct_ast.value_date as value_date,
    fct_ast.loaded_at as loaded_at
from ptf
inner join fct_ast on ptf.ptf_id = fct_ast.ptf_id