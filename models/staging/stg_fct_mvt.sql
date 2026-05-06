with st0_fct_mvt as (
    select * from {{ source('st0', 'st0_fct_mvt') }}
)

select
    cd_fct_mvt as fct_mvt_id,
    cd_fct_ope as fct_ope_id,
    cd_ptf as ptf_id,
    cd_ast as asset_id,
    cd_mvt_typ as mvt_typ_id,
    dt_cta as value_date,
    mt_mvt as amount,
    mt_mvt_ref as amount_ref,
    cd_ccy_mvt as currency,
    ts_stg as loaded_at
from st0_fct_mvt
