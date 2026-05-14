{{
    config(
        materialized='incremental',
        unique_key='cd_ope_typ'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_ope_typ') }}
),

{% if is_incremental() %}
existing as (
    select cd_ope_typ, id_stg_ope_typ from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_ope_typ), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_ope_typ                                            as existing_id,
        row_number() over (
            partition by (e.cd_ope_typ is null)
            order by s.cd_ope_typ
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ope_typ)                  as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_ope_typ = e.cd_ope_typ
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
    )                                                               as id_stg_ope_typ,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1015 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_ope_typ' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_ope_typ                                                      as cd_ope_typ_src,
    cd_ope_typ,
    lb_ope_typ,
    yn_nnm,
    yn_int,
    yn_loa

from enriched