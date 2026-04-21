with ptf as (
    select * from {{ ref('stg_dim_ptf') }}
),

fct_ope as (
    select * from {{ ref('stg_fct_ope') }}
)

select
    ptf.ptf_id,
    ptf.client_id,
    fct_ope.asset_id,
    fct_ope.currency,
    sum(
        case
            when ope_type = 'BUY' then quantity
            when ope_type = 'SELL' then -quantity
            else 0
        end
    ) as amount_position
from ptf
inner join fct_ope on ptf.ptf_id = fct_ope.ptf_id
group by
ptf.ptf_id,
ptf.client_id,
fct_ope.asset_id,
fct_ope.currency
