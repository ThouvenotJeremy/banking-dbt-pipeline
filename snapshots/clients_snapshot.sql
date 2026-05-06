{% snapshot clients_snapshot %}

{{
    config(
        target_schema= 'main' if target.type == 'duckdb' else 'PUBLIC',
        unique_key='client_id',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

select * from {{ ref('stg_cli') }}

{% endsnapshot %}