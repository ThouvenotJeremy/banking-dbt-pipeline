{% snapshot portfolio_snapshot %}

{{
    config(
        target_schema='PUBLIC',
        unique_key='ptf_id',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

select * from {{ ref('stg_dim_ptf') }}

{% endsnapshot %}