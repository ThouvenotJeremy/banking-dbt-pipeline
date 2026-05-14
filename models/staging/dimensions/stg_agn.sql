{{
    config(
        materialized='incremental',
        unique_key='cd_agn'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_agn') }}
),

{% if is_incremental() %}
existing as (
    select cd_agn, id_stg_agn from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_agn), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_agn                                                as existing_id,
        row_number() over (
            partition by (e.cd_agn is null)
            order by s.cd_agn
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_agn)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_agn = e.cd_agn
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
    )                                                               as id_stg_agn,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1003 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_agn' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_agn                                                          as cd_agn_src,
    cd_agn,
    lb_agn

from enriched