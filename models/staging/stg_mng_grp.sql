{{
    config(
        materialized='incremental',
        unique_key='cd_mng_grp'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_mng_grp') }}
),

{% if is_incremental() %}
existing as (
    select cd_mng_grp, id_stg_mng_grp from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_mng_grp), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_mng_grp                                            as existing_id,
        row_number() over (
            partition by (e.cd_mng_grp is null)
            order by s.cd_mng_grp
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_mng_grp)                  as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_mng_grp = e.cd_mng_grp
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
    )                                                               as id_stg_mng_grp,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1014 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_mng_grp' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_mng_grp                                                      as cd_mng_grp_src,
    cd_mng_grp,
    lb_mng_grp

from enriched
