{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CD_PTF'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with fct_ast as (
    select * from {{ ref('int_fct_ast') }}
),

ptf as (
    select * from {{ ref('int_ptf') }}
),

ins as (
    select * from {{ ref('int_ins') }}
)

select
    fct_ast.dt_fct,
    fct_ast.cd_ptf,
    fct_ast.cd_cli,
    ptf.lb_ptf,
    ptf.cd_prf,
    ptf.lb_prf,
    fct_ast.cd_ast,
    ins.lb_ins                                          as asset_name,
    ins.cd_ins_grp                                      as asset_class,
    ins.lb_ins_grp                                      as asset_class_name,
    fct_ast.cd_ccy,
    fct_ast.qt_ast,

    -- Valorisation
    fct_ast.mt_ast,
    fct_ast.mt_ast_ref,

    -- P&L
    fct_ast.mt_pnl,
    fct_ast.mt_pnl_ref,

    -- Performance
    fct_ast.rt_prm,
    fct_ast.rt_pam,
    fct_ast.pc_twr,

    current_timestamp                                   as loaded_at

from fct_ast
inner join ptf
    on fct_ast.cd_ptf = ptf.cd_ptf
    and fct_ast.dt_fct = ptf.dt_fct
left join ins
    on fct_ast.cd_ins = ins.cd_ins
order by fct_ast.dt_fct desc, fct_ast.cd_ptf, fct_ast.cd_ast