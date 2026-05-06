with st0_dim_ptf as (
    select * from {{ source('st0', 'st0_ptf') }}
)
    select
        cd_ptf as ptf_id,
        lb_ptf as ptf_name,
        cd_cli as client_id,
        cd_ccy as currency,
        cd_prf as risk_profile,
        cd_mng as manager_id,
        cast(dt_cre as date) as opening_date,
        dt_clo as closing_date, 
        cast(ts_stg as date) as loaded_at
    from st0_dim_ptf