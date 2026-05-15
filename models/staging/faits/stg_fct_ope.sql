{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ope'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_fct_ope') }}
),

{% if is_incremental() %}
existing as (
    select cd_fct_ope, id_stg_fct_ope from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_fct_ope), 0) as val from {{ this }}
),
{% endif %}

new_records as (
    select
        s.*,
        row_number() over (order by s.dt_cta, s.cd_fct_ope)        as rn
    from source s
    {% if is_incremental() %}
    where s.cd_fct_ope not in (select cd_fct_ope from existing)
    {% endif %}
)

select
    cast(
        {% if is_incremental() %}
        (select val from max_id) + rn
        {% else %}
        rn
        {% endif %}
    as decimal(15,0))                                               as id_stg_fct_ope,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1021 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_fct_ope' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_fct_ope,
    cd_ope,
    cast(nb_seq_ptc as decimal(15,0))                               as nb_seq_ptc,
    lb_fct_ope,
    cd_fct_ope_ext,
    cd_ope_typ,
    cd_deb_crd,
    yn_pro,
    cd_pos,
    cd_ptf,
    cd_ccy_ope,
    cd_ast,
    cd_ins,
    cast(dt_cta as date)                                            as dt_cta,
    cast(dt_exe as date)                                            as dt_exe,
    cast(dt_val as date)                                            as dt_val,
    cast(qt_ope as decimal(26,11))                                  as qt_ope,
    cast(mt_ope as decimal(19,4))                                   as mt_ope,
    cast(mt_net as decimal(19,4))                                   as mt_net

from new_records