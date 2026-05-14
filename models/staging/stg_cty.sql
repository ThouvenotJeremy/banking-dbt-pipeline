{{
    config(
        materialized='incremental',
        unique_key='cd_cty'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_cty') }}
),

{% if is_incremental() %}
existing as (
    select cd_cty, id_stg_cty from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_cty), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_cty                                                as existing_id,
        row_number() over (
            partition by (e.cd_cty is null)
            order by s.cd_cty
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_cty)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_cty = e.cd_cty
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
    )                                                               as id_stg_cty,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1008 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_cty' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_cty                                                          as cd_cty_src,
    cd_cty,
    lb_cty

from enriched
