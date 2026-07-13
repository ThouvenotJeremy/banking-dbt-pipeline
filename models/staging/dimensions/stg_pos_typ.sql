{{
    config(
        materialized='incremental',
        unique_key='cd_pos_typ'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_pos_typ') }}
),

{% if is_incremental() %}
existing as (
    select cd_pos_typ, id_stg_pos_typ from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_pos_typ), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_pos_typ                                            as existing_id,
        row_number() over (
            partition by (e.cd_pos_typ is null)
            order by s.cd_pos_typ
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_pos_typ)                  as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_pos_typ = e.cd_pos_typ
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
    )                                                               as id_stg_pos_typ,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1023 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_pos_typ' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_pos_typ                                                      as cd_pos_typ_src,
    cd_pos_typ,
    lb_pos_typ

from enriched
