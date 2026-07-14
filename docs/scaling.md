# De la démo à la production : notes de scaling

Ce projet tourne aujourd'hui sur un jeu de données de démonstration :
quelques dizaines de lignes par table de fait (`seeds/st0_fct_ast.csv`,
`st0_fct_ope.csv`, `st0_fct_mvt.csv` ont chacun entre 10 et 18 lignes),
sur DuckDB en local. Ce document explique, modèle par modèle, où les choix
actuels casseraient à un volume de production bancaire réaliste — de l'ordre
du million de positions valorisées quotidiennement et de dizaines de milliers
d'opérations par jour — et ce qu'il faudrait changer. Rien ici n'est appliqué
au code : c'est une note d'intention, pas une migration en cours.

## 1. Stratégie incrémentale des faits

Les 4 modèles de faits intermediate (`int_fct_ast`, `int_fct_ope`,
`int_fct_mvt`, `int_fct_ptf`) filtrent les nouvelles lignes de la même façon.
Extrait de [`models/intermediate/int_fct_ast.sql`](../models/intermediate/int_fct_ast.sql) :

```sql
with fct_ast as (
    select * from {{ ref('stg_fct_ast') }}
    {% if is_incremental() %}
    where cd_fct_ast not in (select cd_fct_ast from {{ this }})
    {% endif %}
),
```

**Limite à l'échelle.** `NOT IN (subquery)` est un anti-join qui oblige le
moteur à matérialiser (ou scanner intégralement) la colonne `cd_fct_ast` de
`{{ this }}` — la table cible déjà construite — pour chaque run, quelle que
soit la taille du batch entrant. Sur DuckDB avec 11 lignes, c'est instantané.
Sur une table de plusieurs dizaines de millions de positions historisées,
c'est un scan complet de la clé métier à chaque exécution, sans aucun
pruning possible : `NOT IN` ne peut pas s'appuyer sur un ordre ou une
partition, contrairement à un filtre sur `dt_fct`.

Un détail supplémentaire, plus discret : ce filtre n'existe qu'à la couche
intermediate. En staging, [`stg_fct_ast.sql`](../models/staging/faits/stg_fct_ast.sql)
ne filtre pas du tout le `source` — il relit et refait un `left join` sur
**toute** la table source à chaque run pour décider quel `id_stg_fct_ast`
attribuer (voir section 2). `stg_fct_ope.sql`, lui, filtre bien via un
`not in` équivalent dans sa CTE `new_records`. Cette incohérence entre
`stg_fct_ast` et `stg_fct_ope` n'est pas volontaire — c'est le genre d'écart
qu'un run de démo à faible volume ne révèle jamais, mais qu'un run de
production le ferait immédiatement (temps de run staging qui explose).

**Évolution proposée.**

- **Filtrage incrémental par date**, le plus direct pour des faits datés
  (`dt_fct` pour `fct_ast`/`fct_ptf`, `dt_cta` pour `fct_ope`/`fct_mvt`) :
  ```sql
  {% if is_incremental() %}
  where dt_fct > (select coalesce(max(dt_fct), '1900-01-01') from {{ this }})
  {% endif %}
  ```
  Ce filtre est sargable : sur Snowflake, avec un `cluster_by=['dt_fct']`
  (voir section 3), il élimine des micro-partitions entières sans les
  lire. C'est un changement de sémantique à assumer : on passe d'un
  anti-join par clé métier (robuste aux réémissions tardives, coûteux) à
  un filtre par date (bon marché, mais suppose que les faits n'arrivent pas
  en retard au-delà de la fenêtre — à valider avec la source Avaloq réelle).
- **`incremental_strategy='merge'`** (déjà le comportement implicite dès
  qu'un `unique_key` est défini) reste adapté pour absorber les corrections
  tardives sur une fenêtre glissante, combiné à un filtre de type
  `where dt_fct >= dateadd(day, -N, current_date)` côté source pour borner
  ce que le `merge` doit comparer.
  `insert_overwrite` sur Snowflake serait l'alternative pour un remplacement
  atomique par partition de date, mais demande que la table soit clusterée/
  partitionnée sur cette même colonne pour rester efficace — cohérent avec
  la section 3.

## 2. Génération d'ID séquentiels dans les dimensions

Toutes les dimensions staging (`stg_cli`, `stg_ptf`, `stg_mng`, etc.)
suivent le pattern de [`stg_cli.sql`](../models/staging/dimensions/stg_cli.sql) :

```sql
{% if is_incremental() %}
existing as (
    select cd_cli, id_stg_cli from {{ this }}
),
max_id as (
    select coalesce(max(id_stg_cli), 0) as val from {{ this }}
),
{% endif %}

enriched as (
    select
        s.*,
        e.id_stg_cli as existing_id,
        row_number() over (
            partition by (e.cd_cli is null)
            order by s.cd_cli
        ) as rn
    from source s
    left join existing e on s.cd_cli = e.cd_cli
)

select
    coalesce(existing_id, (select val from max_id) + rn) as id_stg_cli,
    ...
```

**Limite à l'échelle.** Deux problèmes distincts :

1. `max_id` fait un `MAX()` sur la table cible entière à chaque run — un
   agrégat global, donc un point de sérialisation. Deux runs concurrents
   (par exemple deux dimensions chargées en parallèle par Airflow, voir
   section 5) ne peuvent pas partager cette logique sans risque de
   collision d'ID si elle était appliquée sur une même table.
2. `row_number() over (partition by (e.cd_cli is null) ...)` doit trier
   l'intégralité des nouvelles lignes pour leur assigner un rang — correct
   et bon marché sur des dimensions (des milliers à quelques millions de
   lignes, chargées en delta), mais c'est un pattern à ID **non déterministe
   d'un run à l'autre pour une même ligne** tant qu'elle n'a pas encore
   d'`existing_id` : l'ordre dépend de ce qui est arrivé dans le même batch.

**Évolution proposée.**

- **Surrogate key par hash** (`dbt_utils.generate_surrogate_key(['cd_cli'])`,
  package déjà présent dans `packages.yml`) : l'ID devient une fonction pure
  du code métier, calculable indépendamment pour chaque ligne, sans lecture
  de la table cible ni tri global. Coût : on perd l'entier séquentiel
  compact (utile pour du clustering ou des jointures bit-map très
  optimisées) au profit d'un hash — négligeable sur Snowflake où le
  pruning par micro-partition ne dépend pas du type de la clé technique.
- **Séquence native Snowflake** (`CREATE SEQUENCE` / `IDENTITY`) réglerait
  le problème de sérialisation mais casse la garantie actuelle du projet
  (« conserver l'ID existant pour les lignes déjà connues ») : une séquence
  ne sait pas qu'une ligne a déjà un ID business-cohérent, elle numérote à
  l'insertion. Il faudrait alors soit accepter que l'ID technique change
  de sémantique (numéro d'insertion plutôt qu'identifiant stable dérivé du
  code métier), soit garder le hash pour la stabilité et réserver la
  séquence à d'autres usages (ex: ID de run). Les deux ne sont pas
  interchangeables sans arbitrage métier.

## 3. Snowflake : clustering et matérialisation des gros faits

Les 4 marts (`mart_aum_ytd`, `mart_client_exposure`, `mart_portfolio_performance`,
`mart_ptf_detail`) déclarent déjà un `cluster_by`, par exemple dans
[`mart_client_exposure.sql`](../models/marts/mart_client_exposure.sql) :

```sql
{{
    config(
        materialized='table',
        cluster_by=['DT_FCT', 'CD_CLI'],
        post_hook=[...]
    )
}}
```

C'est le bon réflexe (date en tête pour un accès par période, puis la
dimension la plus filtrée par les requêtes BI attendues), mais deux
points méritent d'être précisés pour un lecteur qui jugerait "production" :

- **`cluster_by` est un no-op silencieux sur DuckDB.** dbt-snowflake est le
  seul adaptateur qui traduit cette config en `CLUSTER BY` réel ; en local
  ça ne fait rien de visible. Le projet ne teste donc jamais l'effet du
  clustering — seule une exécution sur un vrai warehouse Snowflake avec un
  volume suffisant (le clustering automatique ne se déclenche qu'au-delà
  d'un nombre de micro-partitions significatif) le validerait.
- **Seule la couche marts est matérialisée en table avec clustering.** La
  couche intermediate est `+materialized: view` par défaut dans
  `dbt_project.yml`, sauf les 4 `int_fct_*` qui overrident explicitement en
  `incremental`. `int_cli`, `int_ptf` et `int_ins` restent des vues : à
  l'échelle démo ça ne coûte rien, mais dès que ces vues encapsulent un
  cross join non trivial (section 4), chaque requête en aval — y compris
  chaque build de mart — recalcule tout depuis zéro à chaque lecture.

**Évolution proposée.** Pour les gros faits, matérialiser en `incremental`
avec `cluster_by=['dt_fct']` (ou `['dt_fct', 'cd_ptf']` selon le pattern
d'accès dominant), comme déjà fait sur les marts — et étendre ce traitement
aux modèles intermediate qui deviennent volumineux (voir section 4), pas
seulement à la couche finale.

## 4. Le cross join calendrier × SCD2 (`int_cli`, `int_ptf`)

[`int_cli.sql`](../models/intermediate/int_cli.sql) (et `int_ptf.sql`, motif
identique) transforme l'historisation SCD2 en un état daté par jour via :

```sql
from calendar cal
cross join source src
left join cty ...
where cal.dt_fct >= src.dt_cre
  and cal.dt_fct >= cast(src.dbt_valid_from as date)
  and (cast(src.dbt_valid_to as date) > cal.dt_fct
       or src.dbt_valid_to is null)
```

`calendar` vient de [`stg_set_cal.sql`](../models/staging/dimensions/stg_set_cal.sql),
qui génère une date par fin de mois entre le **1er janvier 2024, codé en
dur**, et aujourd'hui, plus la date du jour :

```sql
select unnest(generate_series(
    date_trunc('month', date '2024-01-01'),
    date_trunc('month', current_date),
    interval '1 month'
)) as month_start
```

**Constat concret, pas une généralité.** `dbt_project.yml` déclare bien
`vars: start_date: '2024-01-01'` — mais cette variable **n'est référencée
nulle part dans le code**. `stg_set_cal.sql` hardcode la même date en dur
au lieu de lire `{{ var('start_date') }}`. Le `var` existe comme s'il avait
été prévu pour borner cette génération, mais le branchement n'a jamais été
fait. C'est exactement le genre d'écart que ce document est censé
révéler plutôt que de le laisser dormir.

**Comportement à l'échelle.** Le `cross join` produit, avant filtrage,
`nb_dates_calendrier × nb_versions_SCD2_totales` lignes. En démo (~10
clients, quelques versions SCD2, un calendrier mensuel sur ~19 mois),
c'est quelques centaines de lignes générées puis filtrées — invisible.
En production avec un calendrier **journalier** (nécessaire pour un
reporting quotidien, pas mensuel) sur plusieurs années, et des centaines
de milliers de clients ayant chacun plusieurs versions SCD2 dans le temps,
le produit cartésien avant filtre devient rapidement ingérable — d'autant
que `int_cli`/`int_ptf` sont des **vues** (section 3) : ce cross join se
réexécute intégralement à chaque lecture, pas une fois par build.

**Évolution proposée.**

1. Brancher `{{ var('start_date') }}` dans `stg_set_cal.sql` — trivial,
   et ça rend la borne configurable par environnement (démo vs prod)
   sans toucher au SQL.
2. Ne plus croiser le calendrier global avec **toutes** les versions SCD2 :
   borner la génération de dates par ligne à sa propre fenêtre de validité
   (`dbt_valid_from`/`dbt_valid_to` de la ligne, pas le calendrier entier),
   par exemple via une table function bornée par ligne plutôt qu'un
   `cross join` suivi d'un `where`. Ça réduit le volume généré à ce qui
   sera effectivement gardé, au lieu de générer large puis filtrer.
3. Matérialiser `int_cli`/`int_ptf` en `incremental`, `cluster_by=['dt_fct']`,
   avec un filtre `where cal.dt_fct > (select max(dt_fct) from {{ this }})`
   pour ne recalculer que les nouvelles dates à chaque run, comme les
   `int_fct_*` (section 1) — au lieu de tout recalculer à chaque lecture
   en tant que vue.

## 5. Orchestration Airflow

Le DAG actuel ([`banking_pipeline_dag.py`](../orchestration/airflow/dags/banking_pipeline_dag.py))
est une chaîne linéaire de `BashOperator` :

```python
start >> dbt_deps >> dbt_seed >> dbt_run_staging >> dbt_snapshot
      >> dbt_run_intermediate >> dbt_run_marts >> dbt_test >> end
```

Chaque tâche appelle `dbt run --select <couche>` en une seule commande —
ce qui respecte bien la contrainte de dépendance stricte entre couches
(non négociable, voir `CLAUDE.md`), mais masque toute parallélisation
possible **à l'intérieur** d'une couche à Airflow : les 4 marts, par
exemple, ne dépendent pas tous les uns des autres (`mart_rm_performance`
dépend de `mart_aum_ytd`, les 3 autres sont indépendants entre eux), mais
Airflow ne voit qu'une seule tâche `dbt_run_marts` — la parallélisation
éventuelle est déléguée entièrement au `--threads` du profil dbt
(actuellement `4` en local, `1` en CI), invisible depuis le DAG.

**Évolutions à l'échelle :**

- **Génération de tâches par modèle** à partir de `manifest.json` (déjà
  produit par le workflow `dbt_docs.yml` à chaque push) via un outil comme
  Cosmos (`astronomer-cosmos`, cohérent avec l'usage d'Astronomer Runtime
  déjà en place) : Airflow piloterait alors le DAG réel de dbt, avec
  parallélisation automatique des modèles indépendants et retry au niveau
  du modèle plutôt qu'au niveau de la couche entière.
- **Sélection par tags** : `dbt_project.yml` définit déjà
  `+tags: ['dim', 'staging']` et `['fct', 'staging']` sans qu'aucune
  commande du projet ne les exploite aujourd'hui (`dbt_ci.yml`,
  `dbt_docs.yml` et le DAG utilisent tous `--select staging` en bloc).
  Ces tags sont prêts à découper les runs plus finement
  (`--select tag:fct,staging` en parallèle de `tag:dim,staging`, par
  exemple) sans attendre la migration vers Cosmos.
- **Reprises.** `default_args` fixe déjà `retries: 2` / `retry_delay: 5min`
  — raisonnable pour un run quotidien de démo. Le vrai gain à l'échelle
  vient surtout de la granularité de tâche ci-dessus : aujourd'hui, un
  échec dans un seul modèle de `dbt_run_marts` fait échouer (et retenter)
  toute la commande `dbt run --select marts`, pas seulement le modèle en
  cause.
- **Cadence.** `schedule="0 23 * * 1-5"` (jours ouvrés, après clôture) est
  cohérent avec un usage EOD/reporting. Si le volume de production exige un
  rafraîchissement intrajournalier de certains faits (positions, cours),
  ça sort du périmètre d'un batch dbt quotidien et demande une réflexion
  distincte (ingestion streaming en amont, dbt sur une fenêtre plus courte)
  — non traité ici, ce n'est pas qu'un problème d'orchestration.
