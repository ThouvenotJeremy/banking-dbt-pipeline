with ins as (
    select * from {{ ref('stg_ins') }}
),

ins_grp as (
    select * from {{ ref('stg_ins_grp') }}
)

select
    ins.id_stg_ins,
    ins.cd_ins,
    ins.lb_ins,
    ins.cd_ins_grp,
    coalesce(ins_grp.lb_ins_grp, ins.cd_ins_grp)           as lb_ins_grp
from ins
left join ins_grp on ins.cd_ins_grp = ins_grp.cd_ins_grp