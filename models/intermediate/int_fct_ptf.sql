with stg_fct_ptf as (
    select * from {{ ref('stg_fct_ptf') }}
)

select
    fct_ptf_id,
    ptf_id,
    dt_fct,
    pc_ptf,
    mt_net_ref      as mt_net,
    mt_aci_ref      as mt_aci,
    mt_lia_ref      as mt_lia,
    mt_pnl_ref      as mt_pnl,
    mt_pnc_ref      as mt_pnc,
    mt_inc_ref      as mt_inc,
    mt_out_ref      as mt_out,
    mt_nnm_inc_ref  as mt_nnm_inc,
    mt_nnm_out_ref  as mt_nnm_out,
    mt_int_inc_ref  as mt_int_inc,
    mt_int_out_ref  as mt_int_out,
    loaded_at
from stg_fct_ptf