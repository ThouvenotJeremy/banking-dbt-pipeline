with st0_fct_ptf as (
    select * from {{ source('st0', 'st0_fct_ptf') }}
)

select
    cd_fct_ptf          as fct_ptf_id,
    cd_ptf              as ptf_id,
    cast(dt_fct as date) as dt_fct,
    mt_net_ref,
    mt_aci_ref,
    mt_lia_ref,
    mt_net_ptf,
    mt_aci_ptf,
    mt_lia_ptf,
    pc_ptf,
    mt_pnl_ref,
    mt_pnl_ptf,
    mt_pnl_cli,
    mt_pnc_ref,
    mt_pnc_ptf,
    mt_pnc_cli,
    mt_inc_ref,
    mt_out_ref,
    mt_nnm_inc_ref,
    mt_nnm_out_ref,
    mt_int_inc_ref,
    mt_int_out_ref,
    cast(ts_stg as date) as loaded_at
from st0_fct_ptf
