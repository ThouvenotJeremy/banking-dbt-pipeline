with st0_fct_ope as (
    select * from {{ source('st0', 'st0_fct_ope') }}
)

select
    cd_fct_ope          as fct_ope_id,
    cd_ope              as ope_id,
    cd_ptf              as ptf_id,
    cd_ast              as asset_id,
    cd_ccy_ope          as currency,
    cd_ope_typ          as ope_type,
    cd_deb_crd          as debit_credit,
    cd_pos              as pos_id,
    cast(dt_cta as date) as accounting_date,
    cast(dt_exe as date) as execution_date,
    cast(dt_val as date) as value_date,
    qt_ope              as quantity,
    mt_ope              as amount,
    mt_ope_ref          as amount_ref,
    mt_ope_ptf          as amount_ptf,
    mt_net              as amount_net,
    mt_net_ref          as amount_net_ref,
    mt_net_ptf          as amount_net_ptf,
    yn_pro              as is_provisional,
    cast(ts_stg as date) as loaded_at
from st0_fct_ope
