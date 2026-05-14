{{
    config(
        materialized='incremental',
        unique_key='cd_mng_ext'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_mng_ext') }}
),

{% if is_incremental() %}
existing as (
    select cd_mng_ext, id_stg_mng_ext from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_mng_ext), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_mng_ext                                            as existing_id,
        row_number() over (
            partition by (e.cd_mng_ext is null)
            order by s.cd_mng_ext
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_mng_ext)                  as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_mng_ext = e.cd_mng_ext
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
    )                                                               as id_stg_mng_ext,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1013 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_mng_ext' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_mng_ext                                                      as cd_mng_ext_src,
    cd_mng_ext,
    lb_mng_ext

from enriched