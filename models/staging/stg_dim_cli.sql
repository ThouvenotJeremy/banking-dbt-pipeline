with source as (
    select * from {{ ref('st0_dim_cli') }}
),

cleaned as (
    select
        cd_cli as client_id,
        lb_cli as client_name,
        cd_cli_cat as client_category,
        cd_ccy as currency,
        cd_cty_dom as country,
        cd_mng_rel as relationship_manager_id,
        cast(dt_cre as date) as opening_date,
        cast(dt_clo as date) as closing_date,
        cast(ts_stg as date) as loaded_at
    from source
)

select * from cleaned
