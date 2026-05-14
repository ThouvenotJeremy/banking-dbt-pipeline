{{
    config(
        materialized='incremental',
        unique_key='cd_prf'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_prf') }}
),

{% if is_incremental() %}
existing as (
    select cd_prf, id_stg_prf from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_prf), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_prf                                                as existing_id,
        row_number() over (
            partition by (e.cd_prf is null)
            order by s.cd_prf
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_prf)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_prf = e.cd_prf
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
    )                                                               as id_stg_prf,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1016 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_prf' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_prf                                                          as cd_prf_src,
    cd_prf,
    lb_prf

from enriched