{{
    config(
        materialized='incremental',
        unique_key='cd_mng'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_mng') }}
),

{% if is_incremental() %}
existing as (
    select cd_mng, id_stg_mng from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_mng), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_mng                                                as existing_id,
        row_number() over (
            partition by (e.cd_mng is null)
            order by s.cd_mng
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_mng)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_mng = e.cd_mng
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
    )                                                               as id_stg_mng,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1012 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_mng' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_mng                                                          as cd_mng_src,
    cd_mng,
    lb_mng,
    cd_mng_grp

from enriched