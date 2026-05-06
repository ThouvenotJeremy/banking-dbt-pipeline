with st0_fct_ast as (
    select * from {{ source('st0', 'st0_fct_ast') }}
)

select
    cd_fct_ast as fct_ast_id,
    cd_pos as pos_id,
    cd_pos_typ as pos_typ_id,
    cd_ptf as ptf_id,
    cd_ast as asset_id,
    cd_ccy as currency,
    qt_ast as quantity,
    mt_ast as amount,
    cast(dt_fct as date) as value_date,
    cast(ts_stg as date) as loaded_at
from st0_fct_ast