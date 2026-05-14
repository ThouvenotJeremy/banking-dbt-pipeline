{{
    config(
        materialized='incremental',
        unique_key='cd_cli_cat'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_cli_cat') }}
),

{% if is_incremental() %}
existing as (
    select cd_cli_cat, id_stg_cli_cat from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_cli_cat), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_cli_cat                                            as existing_id,
        row_number() over (
            partition by (e.cd_cli_cat is null)
            order by s.cd_cli_cat
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_cli_cat)                  as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_cli_cat = e.cd_cli_cat
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
    )                                                               as id_stg_cli_cat,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1007 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_cli_cat' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_cli_cat                                                      as cd_cli_cat_src,
    cd_cli_cat,
    lb_cli_cat

from enriched