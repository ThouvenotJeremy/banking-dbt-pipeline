{% snapshot portfolio_snapshot %}

{{
    config(
        target_schema='main' if target.type == 'duckdb' else 'PUBLIC',
        unique_key='cd_ptf',
        strategy='timestamp',
        updated_at='ts_stg'
    )
}}

select * from {{ ref('stg_ptf') }}

{% endsnapshot %}