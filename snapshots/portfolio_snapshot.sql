{% snapshot portfolio_snapshot %}

{{
    config(
        target_schema= 'main' if target.type == 'duckdb' else 'PUBLIC',
        unique_key='ptf_id',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

select * from {{ ref('stg_ptf') }}

{% endsnapshot %}