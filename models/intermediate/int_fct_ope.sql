{{
  config(
    materialized='incremental',
    unique_key='fct_ope_id',
    on_schema_change='fail'
  )
}}

with stg_fct_ope as (
    select * from {{ ref('stg_fct_ope') }}
)

select
    fct_ope_id,
    ope_id,
    ptf_id,
    asset_id,
    currency,
    ope_type,
    accounting_date,
    value_date,
    quantity,
    amount,
    amount_ref,
    is_provisional,
    loaded_at
from stg_fct_ope

{% if is_incremental() %}
where loaded_at > (select max(loaded_at) from {{ this }})
{% endif %}
