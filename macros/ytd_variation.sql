{% macro ytd_variation_pct(current_amount, start_amount) %}
    case
        when {{ start_amount }} is null or {{ start_amount }} = 0 then 0
        else (({{ current_amount }} - {{ start_amount }}) / {{ start_amount }}) * 100
    end
{% endmacro %}


{% macro ytd_variation_abs(current_amount, start_amount) %}
    {{ current_amount }} - coalesce({{ start_amount }}, 0)
{% endmacro %}


{% macro ytd_start_lookup(daily_relation, partition_by, date_column, amount_column, calendar_relation) %}

select
    base.*,
    ytd_start.{{ amount_column }} as {{ amount_column }}_ytd_start,
    {{ ytd_variation_pct('base.' ~ amount_column, 'ytd_start.' ~ amount_column) }} as {{ amount_column }}_ytd_variation_pct,
    {{ ytd_variation_abs('base.' ~ amount_column, 'ytd_start.' ~ amount_column) }} as {{ amount_column }}_ytd_variation_abs

from {{ daily_relation }} as base
left join {{ daily_relation }} as ytd_start
    on {% for col in partition_by %}base.{{ col }} = ytd_start.{{ col }}{% if not loop.last %} and {% endif %}{% endfor %}

    and ytd_start.{{ date_column }} = (
        select min({{ date_column }})
        from {{ calendar_relation }}
        where extract(year from {{ date_column }}) = extract(year from base.{{ date_column }})
    )

{% endmacro %}
