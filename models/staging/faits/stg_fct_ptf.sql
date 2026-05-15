{{
    config(
        materialized='incremental',
        unique_key='cd_fct_ptf'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_fct_ptf') }}
),

{% if is_incremental() %}
existing as (
    select cd_fct_ptf, id_stg_fct_ptf from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_fct_ptf), 0) as val from {{ this }}
),
{% endif %}

new_records as (
    select
        s.*,
        row_number() over (order by s.cd_ptf, s.dt_fct)            as rn
    from source s
    {% if is_incremental() %}
    where s.cd_fct_ptf not in (select cd_fct_ptf from existing)
    {% endif %}
)

select
    cast(
        {% if is_incremental() %}
        (select val from max_id) + rn
        {% else %}
        rn
        {% endif %}
    as decimal(15,0))                                               as id_stg_fct_ptf,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1020 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_fct_ptf' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_fct_ptf,
    cd_ptf,
    cast(dt_fct as date)                                            as dt_fct,
    cast(pc_ptf as decimal(26,11))                                  as pc_ptf,
    cast(mt_net as decimal(19,4))                                   as mt_net,
    cast(mt_aci as decimal(19,4))                                   as mt_aci,
    cast(mt_lia as decimal(19,4))                                   as mt_lia,
    cast(mt_pnl as decimal(19,4))                                   as mt_pnl,
    cast(mt_pnc as decimal(19,4))                                   as mt_pnc,
    cast(mt_inc_ytd as decimal(19,4))                               as mt_inc_ytd,
    cast(mt_out_ytd as decimal(19,4))                               as mt_out_ytd,
    cast(mt_nnm_inc_ytd as decimal(19,4))                           as mt_nnm_inc_ytd,
    cast(mt_nnm_out_ytd as decimal(19,4))                           as mt_nnm_out_ytd,
    cast(mt_int_inc_ytd as decimal(19,4))                           as mt_int_inc_ytd,
    cast(mt_int_out_ytd as decimal(19,4))                           as mt_int_out_ytd,
    cast(mt_inc_mtd as decimal(19,4))                               as mt_inc_mtd,
    cast(mt_out_mtd as decimal(19,4))                               as mt_out_mtd,
    cast(mt_nnm_inc_mtd as decimal(19,4))                           as mt_nnm_inc_mtd,
    cast(mt_nnm_out_mtd as decimal(19,4))                           as mt_nnm_out_mtd,
    cast(mt_int_inc_mtd as decimal(19,4))                           as mt_int_inc_mtd,
    cast(mt_int_out_mtd as decimal(19,4))                           as mt_int_out_mtd,
    cast(mt_inc_dtd as decimal(19,4))                               as mt_inc_dtd,
    cast(mt_out_dtd as decimal(19,4))                               as mt_out_dtd,
    cast(mt_nnm_inc_dtd as decimal(19,4))                           as mt_nnm_inc_dtd,
    cast(mt_nnm_out_dtd as decimal(19,4))                           as mt_nnm_out_dtd,
    cast(mt_int_inc_dtd as decimal(19,4))                           as mt_int_inc_dtd,
    cast(mt_int_out_dtd as decimal(19,4))                           as mt_int_out_dtd

from new_records