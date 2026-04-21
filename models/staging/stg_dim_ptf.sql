with source as (
    select * from {{ ref('st0_dim_ptf') }}
),

cleaned as (
    select
        cd_ptf as ptf_id,
        lb_ptf as ptf_name,
        cd_cli as client_id,
        cd_ccy as currency,
        cd_prf as risk_profile,
        cd_mng as manager_id,
        cast(dt_cre as date) as opening_date,
        cast(dt_clo as date) as closing_date,
        cast(ts_stg as date) as loaded_at
    from source
)

select * from cleaned
