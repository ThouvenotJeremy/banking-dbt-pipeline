{% snapshot clients_snapshot %}

{{
    config(
        target_schema='PUBLIC',
        unique_key='client_id',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

select * from {{ ref('stg_dim_cli') }}

{% endsnapshot %}