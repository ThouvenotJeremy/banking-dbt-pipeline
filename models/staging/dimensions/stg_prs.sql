{{
    config(
        materialized='incremental',
        unique_key='cd_prs'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_prs') }}
),

{% if is_incremental() %}
existing as (
    select cd_prs, id_stg_prs from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_prs), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_prs                                                as existing_id,
        row_number() over (
            partition by (e.cd_prs is null)
            order by s.cd_prs
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_prs)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_prs = e.cd_prs
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
    )                                                               as id_stg_prs,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1017 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_prs' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_prs                                                          as cd_prs_src,
    cd_prs,
    lb_prs,
    yn_php,
    cast(dt_bth as date)                                            as dt_bth,
    cast(dt_dth as date)                                            as dt_dth,
    cd_gnd,
    cd_prs_typ,
    cd_cty_nat,
    cd_cty_dom

from enriched