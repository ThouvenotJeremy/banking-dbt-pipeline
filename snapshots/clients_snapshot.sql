{% snapshot clients_snapshot %}

{{
    config(
        target_schema='main' if target.type == 'duckdb' else 'PUBLIC',
        unique_key='cd_cli',
        strategy='timestamp',
        updated_at='ts_stg'
    )
}}

select * from {{ ref('stg_cli') }}

{% endsnapshot %}