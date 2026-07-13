{#
    Test générique : cohérence d'une conversion de devise.
    Vérifie que column_name (le montant converti, ex: _ref) est bien égal à
    native_column * rate_column, à une tolérance d'arrondi près.
    Retourne les lignes en écart — le test échoue si la moindre ligne est retournée.
#}

{% test currency_conversion_consistency(model, column_name, native_column, rate_column, tolerance=0.01) %}

select
    *,
    {{ native_column }} * {{ rate_column }}                            as expected_{{ column_name }},
    abs({{ column_name }} - ({{ native_column }} * {{ rate_column }})) as ecart
from {{ model }}
where abs({{ column_name }} - ({{ native_column }} * {{ rate_column }})) > {{ tolerance }}

{% endtest %}
