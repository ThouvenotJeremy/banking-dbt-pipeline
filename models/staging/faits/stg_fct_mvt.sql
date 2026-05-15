{{
    config(
        materialized='incremental',
        unique_key='cd_fct_mvt'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_fct_mvt') }}
),

{% if is_incremental() %}
existing as (
    select cd_fct_mvt, id_stg_fct_mvt from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_fct_mvt), 0) as val from {{ this }}
),
{% endif %}

new_records as (
    select
        s.*,
        row_number() over (order by s.dt_cta, s.cd_fct_mvt)        as rn
    from source s
    {% if is_incremental() %}
    where s.cd_fct_mvt not in (select cd_fct_mvt from existing)
    {% endif %}
)

select
    cast(
        {% if is_incremental() %}
        (select val from max_id) + rn
        {% else %}
        rn
        {% endif %}
    as decimal(15,0))                                               as id_stg_fct_mvt,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1022 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_fct_mvt' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_fct_mvt,
    cd_pos,
    cd_fct_ope,
    yn_ext,
    cast(dt_cta as date)                                            as dt_cta,
    cast(id_obj_mvt_cat as decimal(15,0))                           as id_obj_mvt_cat,
    cd_mvt_typ,
    cd_ptf,
    cd_mvt_res,
    cd_ast,
    cd_ins,
    cd_ccy_mvt,
    cast(mt_mvt as decimal(19,4))                                   as mt_mvt

from new_records