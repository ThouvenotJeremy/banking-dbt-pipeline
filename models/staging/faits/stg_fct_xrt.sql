{{
    config(
        materialized='incremental',
        unique_key='cd_fct_xrt'
    )
}}

with source as (
    select * from {{ source('st0', 'st0_fct_xrt') }}
),

{% if is_incremental() %}
existing as (
    select cd_fct_xrt, id_stg_fct_xrt from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_fct_xrt), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        {% if is_incremental() %}
        e.id_stg_fct_xrt                                            as existing_id,
        row_number() over (
            partition by (e.cd_fct_xrt is null)
            order by s.cd_ccy, s.dt_fct
        )                                                           as rn
        {% else %}
        row_number() over (order by s.cd_ccy, s.dt_fct)            as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_fct_xrt = e.cd_fct_xrt
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
    )                                                               as id_stg_fct_xrt,

    current_timestamp                                               as ts_stg,
    cast(strftime(current_timestamp, '%Y%m%d') as decimal(15,0))   as vr_stg,
    cast(1018 as decimal(15,0))                                     as id_obj_tec,
    cast('st0_fct_xrt' as varchar)                                  as cd_src,
    cast('{{ invocation_id }}' as varchar)                          as cd_pid,
    cast(null as varchar)                                           as lb_dsc,
    cd_fct_xrt,
    cd_ccy,
    cast(dt_fct as date)                                            as dt_fct,
    cast(rt_fac as decimal(26,11))                                  as rt_fac,
    cast(rt_val as decimal(26,11))                                  as rt_val

from enriched