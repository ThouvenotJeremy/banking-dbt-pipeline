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

daily_aum as (
    select
        fct_ast.dt_fct,
        fct_ast.cd_cli,
        fct_ast.cd_ptf,
        ptf.lb_ptf,
        cli.lb_cli,
        cli.cd_cli_cat,
        cli.lb_cli_cat,
        cli.cd_cty_dom,
        cli.lb_cty_dom,
        cli.cd_ccy                  as cd_ccy_cli,
        ptf.cd_mng,
        ptf.lb_mng,
        ptf.cd_prf,
        ptf.lb_prf,
        current_date                as performance_date,
        sum(fct_ast.mt_ast_ref)     as aum
    from fct_ast
    inner join ptf on fct_ast.cd_ptf = ptf.cd_ptf
                  and fct_ast.dt_fct = ptf.dt_fct
    inner join cli on fct_ast.cd_cli = cli.cd_cli
                  and fct_ast.dt_fct = cli.dt_fct
    group by
        fct_ast.dt_fct,
        fct_ast.cd_cli,
        fct_ast.cd_ptf,
        ptf.lb_ptf,
        cli.lb_cli,
        cli.cd_cli_cat,
        cli.lb_cli_cat,
        cli.cd_cty_dom,
        cli.lb_cty_dom,
        cli.cd_ccy,
        ptf.cd_mng,
        ptf.lb_mng,
        ptf.cd_prf,
        ptf.lb_prf,
        current_date
),

ytd_calculation as (
    {{ ytd_start_lookup(
        daily_relation='daily_aum',
        partition_by=['cd_cli', 'cd_ptf'],
        date_column='dt_fct',
        amount_column='aum',
        calendar_relation=ref('int_set_cal')
    ) }}
)

select
    dt_fct,
    cd_cli,
    cd_ptf,
    lb_ptf,
    lb_cli,
    cd_cli_cat,
    lb_cli_cat,
    cd_cty_dom,
    lb_cty_dom,
    cd_ccy_cli,
    cd_mng,
    lb_mng,
    cd_prf,
    lb_prf,
    aum                          as aum_current,
    aum_ytd_start,
    aum_ytd_variation_pct,
    aum_ytd_variation_abs,
    performance_date,
    current_timestamp            as loaded_at
from ytd_calculation
{% if var("aum_year") is not none %}
where extract(year from dt_fct) = {{ var("aum_year") }}
{% endif %}
order by dt_fct desc, cd_cli, cd_ptf
