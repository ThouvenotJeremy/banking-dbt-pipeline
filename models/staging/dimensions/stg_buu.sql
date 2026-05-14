{{
    config(
        materialized='incremental',
        unique_key='cd_buu'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_buu') }}
),

{% if is_incremental() %}
existing as (
    select cd_buu, id_stg_buu from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_buu), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_buu                                                as existing_id,
        row_number() over (
            partition by (e.cd_buu is null)
            order by s.cd_buu
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_buu)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_buu = e.cd_buu
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
    )                                                               as id_stg_buu,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1005 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_buu' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_buu                                                          as cd_buu_src,
    cd_buu,
    lb_buu

from enriched