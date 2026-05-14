{{
    config(
        materialized='incremental',
        unique_key='cd_cli'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_cli') }}
),

{% if is_incremental() %}
existing as (
    select cd_cli, id_stg_cli from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_cli), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_cli                                                as existing_id,
        row_number() over (
            partition by (e.cd_cli is null)
            order by s.cd_cli
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_cli)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_cli = e.cd_cli
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
    )                                                               as id_stg_cli,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1001 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_cli' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                        as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_cli                                                          as cd_cli_src,
    cd_cli,
    lb_cli,
    lb_cli_alt,
    cast(dt_cre as date)                                            as dt_cre,
    cast(dt_clo as date)                                            as dt_clo,
    cd_cty_dom,
    cd_cty_nat,
    cd_mng_rel,
    cd_cli_cat,
    cd_ccy

from enriched