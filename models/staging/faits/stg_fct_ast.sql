{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ast'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_fct_ast') }}
),

{% if is_incremental() %}
existing as (
    select cd_fct_ast, id_stg_fct_ast from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_fct_ast), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_fct_ast                                            as existing_id,
        row_number() over (
            partition by (e.cd_fct_ast is null)
            order by s.cd_ptf, s.dt_fct, s.cd_ast
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ptf, s.dt_fct, s.cd_ast) as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_fct_ast = e.cd_fct_ast
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
    )                                                               as id_stg_fct_ast,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1019 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_fct_ast' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_fct_ast,
    cd_pos,
    cd_pos_typ,
    cd_ptf,
    cast(dt_fct as date)                                            as dt_fct,
    cd_ccy,
    cd_ins,
    cd_ast,
    lb_fct_ast,
    cast(qt_ast as decimal(26,11))                                  as qt_ast,
    cast(mt_ast as decimal(19,4))                                   as mt_ast,
    cast(mt_aci as decimal(19,4))                                   as mt_aci,
    cast(rt_prm as decimal(26,11))                                  as rt_prm,
    cast(rt_pam as decimal(26,11))                                  as rt_pam,
    cast(mt_pnl as decimal(19,4))                                   as mt_pnl,
    cast(pc_twr as decimal(26,11))                                  as pc_twr

from enriched