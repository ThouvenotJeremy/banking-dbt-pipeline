{#
    Test générique : cohérence d'une conversion de devise via pivot CHF.
    Vérifie que column_name (le montant converti, ex: _ptf) est bien égal à
    native_column * rate_column / pivot_rate_column, à une tolérance d'arrondi près.
    Utilisé quand la conversion passe par deux taux (devise source → CHF → devise
    du portefeuille), contrairement à currency_conversion_consistency qui ne gère
    qu'un seul taux (conversion directe vers CHF, colonnes _ref).
    Retourne les lignes en écart — le test échoue si la moindre ligne est retournée.
#}

{% test currency_pivot_conversion_consistency(model, column_name, native_column, rate_column, pivot_rate_column, tolerance=0.01) %}

select
    *,
    {{ native_column }} * {{ rate_column }} / {{ pivot_rate_column }}                            as expected_{{ column_name }},
    abs({{ column_name }} - ({{ native_column }} * {{ rate_column }} / {{ pivot_rate_column }})) as ecart
from {{ model }}
where abs({{ column_name }} - ({{ native_column }} * {{ rate_column }} / {{ pivot_rate_column }})) > {{ tolerance }}

{% endtest %}
