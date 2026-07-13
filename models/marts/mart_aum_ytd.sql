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
    select
        current_aum.dt_fct,
        current_aum.cd_cli,
        current_aum.cd_ptf,
        current_aum.lb_ptf,
        current_aum.lb_cli,
        current_aum.cd_cli_cat,
        current_aum.lb_cli_cat,
        current_aum.cd_cty_dom,
        current_aum.lb_cty_dom,
        current_aum.cd_ccy_cli,
        current_aum.cd_mng,
        current_aum.lb_mng,
        current_aum.cd_prf,
        current_aum.lb_prf,
        current_aum.aum             as aum_current,
        ytd_start.aum               as aum_ytd_start,
        case
            when ytd_start.aum is null or ytd_start.aum = 0 then 0
            else ((current_aum.aum - ytd_start.aum) / ytd_start.aum) * 100
        end                         as aum_ytd_variation_pct,
        current_aum.aum - coalesce(ytd_start.aum, 0) as aum_ytd_variation_abs,
        current_aum.performance_date,
        current_timestamp           as loaded_at
    from daily_aum current_aum
    left join daily_aum ytd_start
        on  current_aum.cd_cli = ytd_start.cd_cli
        and current_aum.cd_ptf = ytd_start.cd_ptf
        and ytd_start.dt_fct = (
            select min(dt_fct)
            from {{ ref('stg_set_cal') }}
            where extract(year from dt_fct) = extract(year from current_aum.dt_fct)
        )
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
    aum_current,
    aum_ytd_start,
    aum_ytd_variation_pct,
    aum_ytd_variation_abs,
    performance_date,
    loaded_at
from ytd_calculation
{% if var("aum_year") is not none %}
where extract(year from dt_fct) = {{ var("aum_year") }}
{% endif %}
order by dt_fct desc, cd_cli, cd_ptf