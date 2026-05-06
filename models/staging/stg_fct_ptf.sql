with st0_fct_ptf as (
    select * from {{ source('st0', 'st0_fct_ptf') }}
)

select
    cd_fct_ptf as fct_ptf_id,
    cd_ptf as ptf_id,
    dt_fct,
    mt_net_ref,
    mt_aci_ref,
    mt_lia_ref,
    mt_pnl_ref,
    mt_inc_ref_mtd,
    mt_out_ref_mtd,
    mt_nnm_inc_ref_mtd,
    mt_nnm_out_ref_mtd,
    ts_stg as loaded_at
from st0_fct_ptf
