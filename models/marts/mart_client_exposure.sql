{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CD_CLI'],
        post_hook=[
            "{% if target.type == 'snowflake' %}grant select on {{ this }} to role BI_READ_ONLY{% endif %}"
        ]
    )
}}

with fct_ast as (
    select * from {{ ref('int_fct_ast') }}
),

cli as (
    select * from {{ ref('int_cli') }}
),

ptf as (
    select * from {{ ref('int_ptf') }}
),

ins as (
    select * from {{ ref('int_ins') }}
)

select
    fct_ast.dt_fct,
    fct_ast.cd_cli,
    cli.lb_cli,
    cli.cd_cli_cat,
    cli.lb_cli_cat,
    cli.cd_cty_dom,
    cli.lb_cty_dom,
    cli.cd_cty_nat,
    fct_ast.cd_ptf,
    ptf.lb_ptf,
    ptf.lb_ptf_alt,
    ptf.cd_mng,
    ptf.lb_mng,
    ptf.cd_mng_grp,
    ptf.lb_mng_grp,
    ptf.cd_mng_ext,
    ptf.lb_mng_ext,
    ptf.cd_agn,
    ptf.lb_agn,
    ptf.cd_ent,
    ptf.lb_ent,
    ptf.cd_buu,
    ptf.lb_buu,
    ptf.cd_prf,
    ptf.lb_prf,
    fct_ast.cd_ast,
    ins.lb_ins                                          as asset_name,
    ins.cd_ins_grp                                      as asset_class,
    ins.lb_ins_grp                                      as asset_class_name,
    fct_ast.cd_ccy,
    fct_ast.xrt_rate_pos                                as xrt_rate,

    fct_ast.mt_ast,
    fct_ast.mt_ast_ref,
    cast(
        {{ safe_divide(
            'fct_ast.mt_ast_ref',
            'sum(fct_ast.mt_ast_ref) over (partition by fct_ast.cd_cli, fct_ast.dt_fct)'
        ) }}
    as double)                                          as weight_pct

from fct_ast
left join cli
    on fct_ast.cd_cli = cli.cd_cli
    and fct_ast.dt_fct = cli.dt_fct
left join ptf
    on fct_ast.cd_ptf = ptf.cd_ptf
    and fct_ast.dt_fct = ptf.dt_fct
left join ins
    on fct_ast.cd_ins = ins.cd_ins