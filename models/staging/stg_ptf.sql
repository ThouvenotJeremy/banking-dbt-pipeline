{{
    config(
        materialized='incremental',
        unique_key='cd_ptf'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_ptf') }}
),

{% if is_incremental() %}
existing as (
    select cd_ptf, id_stg_ptf from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_ptf), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_ptf                                                as existing_id,
        row_number() over (
            partition by (e.cd_ptf is null)
            order by s.cd_ptf
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ptf)                      as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_ptf = e.cd_ptf
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
    )                                                               as id_stg_ptf,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1002 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_ptf' as varchar)                                      as cd_src,
    cast('{{ invocation_id }}' as varchar)                         as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cast(1 as decimal(15,0))                                        as id_ptf_tec_typ,
    cd_ptf                                                          as cd_ptf_src,
    cd_ptf,
    lb_ptf,
    lb_ptf_alt,
    cast(dt_cre as date)                                            as dt_cre,
    cast(dt_clo as date)                                            as dt_clo,
    cd_cli,
    cd_ccy,
    cd_prf,
    cd_mng,
    cd_mng_ext,
    cd_agn,
    cd_ent,
    cd_buu

from enriched