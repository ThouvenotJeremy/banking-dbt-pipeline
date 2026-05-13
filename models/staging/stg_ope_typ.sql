with st0_ope_typ as (
    select * from {{ ref('st0_ope_typ') }}
)

select
    cd_ope_typ                              as ope_typ_id,
    lb_ope_typ                              as ope_typ_name,
    case when yn_nnm = 'Y' then true else false end as is_nnm,
    case when yn_int = 'Y' then true else false end as is_interest,
    case when yn_loa = 'Y' then true else false end as is_loan,
    ts_stg                                  as loaded_at
from st0_ope_typ