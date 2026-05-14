{{
    config(
        materialized='incremental',
        unique_key='cd_ccy'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_ccy') }}
),

{% if is_incremental() %}
existing as (
    select cd_ccy, id_stg_ccy from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_ccy), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_ccy                                                as existing_id,
        row_number() over (
            partition by (e.cd_ccy is null)
            order by s.cd_ccy
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ccy)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_ccy = e.cd_ccy
    {% endif %}
)

select
    cast(
        coalesce(
            {% if is_incremental() %}
            existing_id,
            (select val from max_id) + rn
            {% else %}
            rn
            {% endif %}
        ) as decimal(15,0)
    )                                                               as id_stg_ccy,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1006 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_ccy' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_ccy                                                          as cd_ccy_src,
    cd_ccy,
    lb_ccy

from enriched