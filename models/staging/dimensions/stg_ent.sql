{{
    config(
        materialized='incremental',
        unique_key='cd_ent'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_ent') }}
),

{% if is_incremental() %}
existing as (
    select cd_ent, id_stg_ent from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_ent), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_ent                                                as existing_id,
        row_number() over (
            partition by (e.cd_ent is null)
            order by s.cd_ent
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ent)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_ent = e.cd_ent
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
    )                                                               as id_stg_ent,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1009 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_ent' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_ent                                                          as cd_ent_src,
    cd_ent,
    lb_ent

from enriched