{{
    config(
        materialized='incremental',
        unique_key='cd_ast'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_ast') }}
),

{% if is_incremental() %}
existing as (
    select cd_ast, id_stg_ast from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_ast), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_ast                                                as existing_id,
        row_number() over (
            partition by (e.cd_ast is null)
            order by s.cd_ast
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ast)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_ast = e.cd_ast
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
    )                                                               as id_stg_ast,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1004 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_ast' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_ast                                                          as cd_ast_src,
    cd_ast,
    lb_ast,
    tt_ast,
    cd_rat

from enriched