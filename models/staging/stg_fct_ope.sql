with st0_fct_ope as (
    select * from {{ source('st0', 'st0_fct_ope') }}
)

select
    cd_fct_ope as fct_ope_id,
    cd_ope as ope_id,
    cd_ptf as ptf_id,
    cd_ast as asset_id,
    cd_ccy_ope as currency,
    cd_ope_typ as ope_type,
    cast(dt_cta as date) as accounting_date,
    cast(dt_val as date) as value_date,
    qt_ope as quantity,
    mt_ope as amount,
    mt_ope_ref as amount_ref,
    yn_pro as is_provisional,
    cast(ts_stg as date) as loaded_at
from st0_fct_ope
