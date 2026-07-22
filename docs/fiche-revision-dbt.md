# Fiche de révision dbt — banking-dbt-pipeline

Fiche orale, basée sur le vrai code du projet. Objectif : ne jamais chercher
ses mots en entretien. Chaque concept a : une phrase de résumé, quand
l'utiliser vs une alternative, un extrait réel, et une ou plusieurs
questions probables avec la réponse orale complète. Finit par un flash
quickfire pour la révision de dernière minute.

---

## FONDAMENTAUX

### `ref()` vs `source()`

**À quoi ça sert.** `source()` pointe vers une table brute déclarée dans
`sources.yml` (une donnée qui n'est pas produite par dbt) ; `ref()` pointe
vers un autre modèle dbt et construit le graphe de dépendances (lineage).

**Quand l'un vs l'autre.** `source()` uniquement en staging — c'est le seul
endroit du projet qui touche la donnée brute. Partout ailleurs (intermediate,
marts), `ref()`, même quand on connaît le nom exact de la table physique
cible.

**Mon code.**
```sql
-- models/staging/dimensions/stg_cli.sql
with source as (
    select * from {{ source('st0', 'st0_cli') }}
),
```
```sql
-- models/intermediate/int_cli.sql
with source as (
    select * from {{ ref('clients_snapshot') }}
),
```

**Q1. "Pourquoi tu utilises `ref()` au lieu d'écrire directement le nom de
la table dans ton `FROM` ? Qu'est-ce que ça te fait gagner concrètement ?"**

*"Trois choses. D'abord et surtout, `ref()` construit le graphe de
dépendances, donc dbt connaît l'ordre de build tout seul — il sait qu'il
doit construire `clients_snapshot` avant `int_cli` qui le lit, sans que
j'aie à le déclarer explicitement quelque part. Ensuite, `ref()` est
indépendant de l'environnement : le même code résout `main` en dev sur
DuckDB et `PUBLIC` en prod sur Snowflake, alors qu'un nom de table en dur
casserait au changement de cible. Et enfin ça donne le lineage complet pour
la doc et l'analyse d'impact — je peux faire `dbt list --select
int_cli+` et savoir instantanément tout ce qui dépend de ce modèle avant d'y
toucher."*

**Q2. "Et `source()`, pourquoi ne pas juste faire `ref()` vers un premier
modèle staging qui fait juste un `select *` de la table brute ?"**

*"Parce que `source()` fait une chose de plus que `ref()` : il documente et
teste la table brute elle-même, indépendamment de tout modèle. Dans
`sources.yml` je décris chaque table `st0_*`, ses colonnes, et je peux y
attacher de la fraîcheur (`freshness`). Si je faisais un modèle staging vide
qui ne fait que lire la source, j'ajouterais une couche sans valeur, et je
perdrais la déclaration explicite 'ceci est une frontière du système, pas
un modèle transformé par dbt' — utile pour distinguer d'un coup d'œil, dans
le lineage généré, ce qui vient de l'extérieur de ce qui est produit par le
pipeline."*

**Piège classique.** Un `mart_*` qui fait `{{ ref('stg_xxx') }}` directement
au lieu de passer par l'intermediate — ça compile, ça teste vert, mais ça
viole la règle de dépendance stricte du projet (voir section ARCHITECTURE).
`ref()` empêche les erreurs *techniques* (nom de table qui change), pas les
erreurs *architecturales* (sauter une couche) — j'ai dû écrire un script à
part pour ça.

---

### Les 3 matérialisations utilisées

**À quoi ça sert.** La matérialisation définit comment dbt persiste le
résultat d'un `select` : `view` (recalculé à chaque lecture), `table`
(recalculé en entier à chaque run), `incremental` (seules les nouvelles
lignes sont ajoutées/fusionnées).

**Quand l'une vs l'autre.**
- `view` : intermediate par défaut (`int_cli`, `int_ptf`, `int_ins`,
  `int_set_cal`) — enrichissement pas trop coûteux, pas besoin de le stocker.
- `table` : marts — surface consommée par le BI, doit être rapide à lire,
  recalculée intégralement à chaque run (le volume le permet).
- `incremental` : staging (dimensions + faits) et les 4 `int_fct_*` — la
  source grossit dans le temps, refaire un `table` complet à chaque run
  devient inutilement coûteux.

**Mon code.**
```yaml
# dbt_project.yml
models:
  banking_pipeline:
    staging:
      dimensions: { +materialized: incremental }
      faits:      { +materialized: incremental }
    intermediate:
      +materialized: view
    marts:
      +materialized: table
```
```sql
-- models/intermediate/int_fct_ast.sql (override du défaut view de la couche)
{{ config(materialized='incremental', unique_key='cd_fct_ast', on_schema_change='fail') }}
```

**Q1. "Tu as un modèle intermediate qui casse la convention `view` par
défaut de sa couche. Pourquoi, et comment tu le justifies ?"**

*"Les 4 modèles `int_fct_*` — positions, opérations, mouvements,
performance portefeuille — lisent des faits qui s'accumulent
indéfiniment. En vue, chaque lecture en aval relancerait le calcul de
conversion devise sur l'historique complet à chaque fois. Passer ces 4
modèles en incrémental, avec un `unique_key` sur le code métier du fait,
c'est le seul cas où je m'écarte du défaut de couche dans
`dbt_project.yml`, et je le fais explicitement dans le `config()` du
modèle — pour que ce soit visible dans le fichier, pas caché dans une
config à part."*

**Q2. "C'est quoi `on_schema_change='fail'` sur ces modèles, et pourquoi
uniquement là ?"**

*"C'est une protection sur les modèles incrémentaux : si le `select` change
de forme — une colonne ajoutée, renommée, supprimée — sans
`--full-refresh`, dbt refuserait par défaut de merger silencieusement un
schéma différent dans la table existante, il ferait planter le run
explicitement. Je l'ai mis sur les 4 `int_fct_*` parce que ce sont des
modèles avec beaucoup de colonnes calculées (les conversions devise) : si
je change une formule et que ça change le typage ou que j'ajoute une
colonne, je préfère un échec net qui me force à faire un `--full-refresh`
conscient, plutôt qu'un comportement par défaut plus permissif qui
masquerait l'incohérence entre l'ancien et le nouveau schéma dans la même
table."*

**Q3. "Pourquoi les marts sont en `table` et pas en vue, alors que
l'intermediate est en vue par défaut — c'est pas contradictoire ?"**

*"Non, parce que le critère n'est pas 'est-ce que c'est une couche
avancée', c'est 'qui lit ce modèle et à quelle fréquence'. Un mart est lu
en direct par un outil BI, potentiellement plusieurs fois par minute, sur
des colonnes agrégées — le recalculer à la volée à chaque requête serait
inutilement lent côté utilisateur final. Un modèle intermediate, lui, n'est
lu que par d'autres modèles dbt pendant un run — le coût de la vue est
absorbé une fois, pas par chaque analyste qui ouvre un dashboard."*

---

### Seeds

**À quoi ça sert.** Un seed est un CSV versionné dans le repo que dbt charge
tel quel en table via `dbt seed` — pas de transformation, juste un
chargement.

**Quand l'utiliser vs une alternative.** Pour des données de référence
statiques et petites, ou ici pour **simuler** l'extraction d'un vrai système
source (Avaloq) sans connexion réelle — en prod, ce serait une vraie
extraction déclarée comme `source()`, pas un seed.

**Mon code.**
```yaml
# dbt_project.yml
seed-paths: ["seeds"]
```
```
seeds/st0_cli.csv
seeds/st0_fct_ast.csv
```
Toutes les tables `st0_*` sont des seeds — jamais de vraie connexion — et la
couche staging les lit via `source()`, exactement comme elle lirait une
vraie extraction demain.

**Q1. "Ton pipeline tourne sur des seeds statiques. Si on te branche une
vraie extraction Avaloq demain, qu'est-ce qui change dans le code ?"**

*"En théorie, rien dans le SQL des modèles. Le seed et une vraie table
externe sont tous les deux consommés via `source('st0', 'st0_cli')` — la
couche staging ne fait pas la différence. Ce qui change, c'est la
déclaration dans `sources.yml` : le schéma/la base pointerait vers la
vraie extraction, et j'activerais la fraîcheur de source que j'ai déjà
préparée en commentaire — `loaded_at_field` sur une vraie colonne
d'extraction, qui n'existe pas encore côté seed."*

**Q2. "Pourquoi ne pas juste utiliser un seed en production, si ça marche
en dev ?"**

*"Parce qu'un seed est fait pour des petits volumes rechargés en entier à
chaque `dbt seed --full-refresh` — il n'y a pas de notion de fraîcheur, pas
d'incrémentalité côté source, pas de connexion réelle à un système
opérationnel. Le seed simule ici une extraction quotidienne, mais il n'a
aucun mécanisme pour signaler qu'un extract est en retard ou a échoué — au
contraire d'une vraie source avec des colonnes de chargement et un contrôle
de fraîcheur. Utiliser un seed en prod, ce serait figer des données de
référence à la main dans git, ce qui n'a de sens que pour des vrais
référentiels rarement modifiés (genre une table de mapping de codes), pas
pour un flux quotidien de positions ou d'opérations."*

---

## INCRÉMENTAL

### `is_incremental()` + `unique_key` : le mécanisme merge

**À quoi ça sert.** `is_incremental()` est un flag Jinja qui devient vrai
uniquement quand la table cible existe déjà et que le run n'est pas un
`--full-refresh` — il permet d'écrire un SQL différent pour "premier build"
et "runs suivants". `unique_key` dit à dbt quelle colonne identifie une
ligne de façon unique, pour qu'il fasse un merge (upsert) au lieu d'un
simple append.

**Quand l'utiliser vs une alternative.** Dès qu'un modèle incrémental peut
revoir une ligne déjà connue (correction, mise à jour), `unique_key` est
obligatoire — sans lui, dbt fait un append aveugle : la ligne existante
reste, la "nouvelle" version s'ajoute à côté, doublon. C'est exactement
l'incident `stg_set_cal` (voir plus bas).

**Mon code.**
```sql
-- models/staging/dimensions/stg_cli.sql
{{ config(materialized='incremental', unique_key='cd_cli') }}

with source as (
    select * from {{ source('st0', 'st0_cli') }}
),
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
        {% if is_incremental() %}
        e.id_stg_cli as existing_id,
        row_number() over (partition by (e.cd_cli is null) order by s.cd_cli) as rn
        {% else %}
        row_number() over (order by s.cd_cli) as rn
        {% endif %}
    from source s
    {% if is_incremental() %}
    left join existing e on s.cd_cli = e.cd_cli
    {% endif %}
)
select
    coalesce(existing_id, (select val from max_id) + rn) as id_stg_cli,
    ...
```

**Q1. "Explique-moi le mécanisme derrière `unique_key` dans un modèle
incrémental. Que se passe-t-il concrètement ?"**

*"Deux choses distinctes se combinent. D'un côté, dbt lui-même : une fois
mon `select` exécuté, il fait un merge basé sur `unique_key` — les lignes
dont la clé existe déjà dans la table cible sont mises à jour, les
nouvelles sont insérées. De l'autre côté, dans mon propre SQL, je gère la
stabilité de l'ID technique : à la première exécution `is_incremental()`
est faux donc je numérote tout avec `row_number()`. Aux runs suivants, je
lis `{{ this }}` — la table déjà construite — via la CTE `existing`, pour
savoir quelles lignes sont déjà connues. Celles-là gardent leur `id_stg_cli`
d'origine. Les nouvelles reçoivent `MAX(id) + row_number()`, calculé
uniquement sur le nouveau lot. Donc `unique_key` gère la fusion au niveau
table, et mon `row_number()` partitionné gère la stabilité de l'identifiant
au niveau ligne — les deux sont nécessaires, l'un ne remplace pas l'autre."*

**Q2. "Pourquoi `partition by (e.cd_cli is null)` dans le `row_number()` ?
Ça sert à quoi précisément ?"**

*"Ça sépare les lignes déjà connues des nouvelles en deux groupes de
partition — `e.cd_cli is null` vaut `false` pour une ligne déjà existante
dans `existing`, `true` pour une ligne nouvelle. Le `row_number()` à
l'intérieur de chaque partition redémarre à 1, donc pour les lignes déjà
connues le rang ne sert à rien — je ne l'utilise jamais, puisque
`coalesce(existing_id, ...)` prend `existing_id` en priorité, qui est déjà
renseigné pour elles. Pour les nouvelles lignes, le rang redémarre proprement
à 1 dans leur propre partition, donc `MAX(id) + rn` leur donne bien des ID
consécutifs à partir du dernier connu, sans être décalé par le nombre de
lignes déjà existantes dans le lot."*

**Q3. "Qu'est-ce qui se passe si je supprime une ligne côté source ? Ton
pattern la gère comment ?"**

*"Il ne la gère pas, et c'est voulu pour ce projet : ce pattern ne fait
jamais de suppression, seulement insert/merge. Une ligne supprimée côté
source resterait dans la table cible avec son dernier état connu — pour
des dimensions comme les clients ou les portefeuilles, la donnée réelle ne
se supprime jamais vraiment, elle se clôture (`dt_clo`). Si j'avais un vrai
besoin de suppression physique, il faudrait soit une stratégie
`incremental_strategy='microbatch'`/`insert_overwrite` avec une fenêtre de
remplacement complet, soit un `post-hook` de nettoyage explicite — mais je
ne l'ai pas dans ce projet parce que le besoin métier ne s'est pas présenté."*

---

### Pourquoi incrémental sur les faits, et l'incident `stg_set_cal`

**À quoi ça sert.** Les faits (positions, opérations) grossissent
indéfiniment ; recalculer tout l'historique à chaque run coûte de plus en
plus cher pour un gain nul sur les lignes déjà traitées. L'incrémental ne
retraite que ce qui est nouveau.

**Mon code (pattern insert-only, faits immuables).**
```sql
-- models/intermediate/int_fct_ast.sql
with fct_ast as (
    select * from {{ ref('stg_fct_ast') }}
    {% if is_incremental() %}
    where cd_fct_ast not in (select cd_fct_ast from {{ this }})
    {% endif %}
),
```

**Q1. "Tu m'as parlé d'un incident avec un modèle incrémental. Raconte-moi
ce qui s'est passé et comment tu l'as détecté."**

*"`stg_set_cal` génère un calendrier de dates. Il était
`materialized='incremental'` depuis sa création, mais sans `unique_key` et
sans filtre `is_incremental()` dans le `select` — donc chaque run
réinjectait le calendrier entier par-dessus l'existant, en pur append, sans
jamais dédoublonner. Le bug était invisible parce qu'aucun test d'unicité
ne portait sur sa colonne de date. Il a été révélé quand j'ai ajouté un
modèle intermediate en passthrough par-dessus, avec un test `unique` sur
cette même colonne — et le CI, qui construit le staging deux fois par
pipeline (`dbt run --select staging` puis un `dbt run` complet), a
déterministement doublé chaque date et fait échouer le test. Le fix a été
d'ajouter `unique_key='dt_fct'` pour forcer dbt à merger au lieu d'append.
Après ça, j'ai audité les 27 autres modèles incrémentaux du projet — tous
avaient déjà un `unique_key`, `stg_set_cal` était le seul oubli, probablement
parce que c'est le seul modèle staging qui **génère** sa donnée au lieu de
lire une source, donc il est sorti du réflexe habituel."*

**Q2. "Pourquoi ce bug n'a pas cassé les tests plus tôt, avant que tu
ajoutes ce test d'unicité ?"**

*"Parce qu'aucun test ne regardait cette colonne, et que la duplication en
elle-même n'empêche pas le pipeline de tourner — ce n'est pas une erreur
SQL, c'est juste des lignes en trop. En aval, les modèles qui utilisaient
ce calendrier faisaient des `min()`/`max()` ou des jointures sur une valeur
de date : des doublons exacts d'une même date n'auraient probablement rien
changé au résultat numérique dans ce cas précis, ce qui explique que
personne ne l'ait remarqué en pratique — mais c'est exactement le genre de
bug qui devient dangereux le jour où quelqu'un fait un `count(*)` sur ce
calendrier en supposant une ligne par jour, ou joint dessus sans dédupliquer
en aval."*

**Q3. "Comment tu as diagnostiqué que c'était spécifiquement le double
build du staging en CI qui causait ça, et pas autre chose ?"**

*"Je n'avais pas accès aux logs bruts du job CI — droits insuffisants sur
l'API GitHub. J'ai reproduit la séquence exacte du workflow en local, à
partir d'une base neuve : seed, `dbt run --select staging`, snapshot, puis
un `dbt run` complet — exactement l'ordre du fichier `dbt_ci.yml`. Le test
d'unicité a échoué avec 31 lignes en double dès cette reproduction, ce qui
confirmait le mécanisme sans ambiguïté. J'ai aussi rejoué deux fois de plus
la séquence complète après le fix pour vérifier que ça ne dérive pas sur
plusieurs runs consécutifs, pas seulement au premier build."*

**Pattern alternatif dans le même projet — insert-only par date plutôt que
par clé.** `stg_fct_ope.sql` utilise un `NOT IN` sur le code métier
(`cd_fct_ope`) dans sa CTE `new_records`, filtrant la **source** avant
insertion — contrairement à `stg_fct_ast.sql` qui, à l'origine, ne filtrait
pas du tout sa source (juste un `left join` pour attribuer les ID). Je l'ai
aligné sur le pattern de `stg_fct_ope` pour la même raison : un fait est
immuable, pas la peine de relire toute la source à chaque run pour décider
quel ID attribuer, un filtre `not in` suffit.

---

## HISTORISATION

### Snapshots SCD2 : stratégie `timestamp`, `dbt_valid_from`/`dbt_valid_to`

**À quoi ça sert.** Un snapshot dbt capture l'état d'une table à chaque run
et versionne les changements dans le temps : chaque ligne obtient
`dbt_valid_from`/`dbt_valid_to`, ce qui permet de reconstituer "l'état à une
date passée" sans écrire la logique SCD2 à la main.

**Quand `timestamp` vs l'alternative `check`.** `timestamp` compare une
colonne qui avance de façon fiable à chaque changement (ici `ts_stg`, mis à
jour à chaque run de staging) — simple et peu coûteux. `check` compare
l'ensemble (ou une liste choisie) de colonnes entre l'ancien et le nouvel
état quand aucune colonne de date fiable n'existe — plus lourd (il faut
comparer valeur par valeur), à réserver au cas où on n'a pas de timestamp
de confiance.

**Mon code.**
```sql
-- snapshots/clients_snapshot.sql
{% snapshot clients_snapshot %}
{{
    config(
        target_schema='main' if target.type == 'duckdb' else 'PUBLIC',
        unique_key='cd_cli',
        strategy='timestamp',
        updated_at='ts_stg'
    )
}}
select * from {{ ref('stg_cli') }}
{% endsnapshot %}
```

**Q1. "Pourquoi un snapshot dbt plutôt que gérer l'historisation toi-même
dans un modèle SQL classique ?"**

*"Parce que la logique SCD2 — détecter qu'une ligne a changé, clôturer
l'ancienne version, ouvrir la nouvelle avec les bonnes dates de validité —
est un pattern générique que dbt implémente correctement une fois pour
toutes. Je n'ai qu'à déclarer la clé et la stratégie de détection de
changement. Si je l'écrivais à la main dans un modèle, ce serait soit un
`table` qui écrase tout à chaque run — donc perte de l'historique — soit
une logique de merge maison à réinventer et maintenir. Et le format
`dbt_valid_from`/`dbt_valid_to` est ensuite exploité directement en
intermediate : `int_cli` croise le calendrier avec ces deux colonnes pour
produire un état daté par jour, sans logique custom supplémentaire."*

**Q2. "`ts_stg` c'est quoi exactement, et pourquoi c'est fiable comme
colonne de détection de changement ?"**

*"`ts_stg` est un `current_timestamp` posé par le modèle staging à chaque
run — donc à chaque fois qu'une ligne est retraitée en staging, `ts_stg`
avance, que la donnée métier ait changé ou non. C'est fiable dans le sens
où elle avance **de façon monotone** — c'est la condition nécessaire pour
que `strategy='timestamp'` fonctionne : dbt compare le `ts_stg` du snapshot
existant à celui de la nouvelle ligne, et si c'est plus récent, il clôture
l'ancienne version. Le vrai point d'attention, c'est que si `ts_stg`
n'avançait pas à chaque run — par exemple si c'était une date business
figée — le snapshot ne détecterait jamais de changement, même si le
contenu a changé."*

**Q3. "Est-ce que tu snapshotes tout ? Pourquoi seulement clients et
portefeuilles ?"**

*"Non, seuls `stg_cli` et `stg_ptf` ont un snapshot. Ce sont les deux
dimensions qui ont un vrai besoin d'historique daté dans ce projet — la
performance et l'exposition sont calculées jour par jour, et un client ou
un portefeuille peut changer de manager, de profil de risque, etc, dans le
temps. Les autres dimensions comme les instruments ou les managers n'ont
pas de snapshot : c'est un point que j'ai identifié moi-même comme un
manque potentiel — si un instrument change de classe d'actif ou qu'un
manager change d'équipe, l'ancien état est perdu. Je ne l'ai pas ajouté
sans validation métier, parce que ajouter un snapshot a un coût de
maintenance et que je ne sais pas si ces attributs changent réellement
assez souvent pour justifier l'historisation."*

---

## TESTS

### Tests génériques vs singuliers

**À quoi ça sert.** Un test générique est paramétrable et réutilisable sur
plusieurs colonnes/modèles (`not_null`, `unique`, ou une macro `{% test %}`
custom) ; un test singulier est une requête SQL ad hoc, écrite une seule
fois pour un cas précis, dans un fichier `.sql` sous `tests/`.

**Quand l'un vs l'autre.** Générique dès que la même vérification s'applique
à plusieurs colonnes ou modèles (structure, cohérence de conversion,
ranges). Singulier pour une règle métier ponctuelle qui ne concerne qu'un
seul modèle et ne se généralise pas.

**Mon code.**
```sql
-- tests/asset_positive_amounts.sql (singulier)
-- En banque privée une position négative = short selling
-- Ce portefeuille ne fait pas de short selling
select *
from {{ ref('mart_client_exposure') }}
where mt_ast < 0
   or mt_ast_ref < 0
```

**Q1. "Comment tu décides si un test doit être générique ou singulier ?"**

*"Je me demande si la règle est réutilisable. `mt_ast < 0` sur un seul
mart, c'est une règle métier locale — pas la peine de la généraliser, un
fichier `.sql` dans `tests/` suffit. Par contre, dès que j'écris deux fois
la même vérification à la main — c'est ce qui s'est passé pour la
cohérence de conversion devise, testée d'abord sur un modèle puis
nécessaire sur trois autres — je transforme ça en test générique custom
avec `{% test %}`, pour ne pas dupliquer le SQL et risquer une divergence
entre les copies."*

**Q2. "Un test singulier, comment dbt sait que c'est un test et pas un
modèle ? Il n'y a pas de mot-clé spécial dans le fichier."**

*"C'est l'emplacement qui fait foi : tout fichier `.sql` sous le dossier
déclaré dans `test-paths` de `dbt_project.yml` — ici `tests/` — est traité
comme un test singulier, jamais comme un modèle. La convention dbt est que
la requête doit retourner les lignes en échec : si le `select` renvoie au
moins une ligne, le test échoue. Il n'y a pas besoin de bloc `{% test %}`
pour un singulier, contrairement à un générique — c'est juste un fichier
SQL brut, avec accès aux mêmes fonctions Jinja (`ref()`, `source()`,
`var()`) que n'importe quel modèle."*

---

### Mes 3 familles de tests

**À quoi ça sert.** Trois niveaux de vérification qui ne se recouvrent pas :
structurels (la donnée est bien formée), cohérence (une valeur calculée est
mathématiquement juste), ranges (une valeur reste dans un intervalle métier
plausible).

**Mon code.**
```yaml
# structurels — intégrité de base
tests: [not_null, unique, accepted_values, relationships]

# cohérence — macros custom (tests/generic/)
- currency_conversion_consistency:      # _ref = natif * taux
    arguments: { native_column: mt_net, rate_column: xrt_rate }
- currency_pivot_conversion_consistency: # _ptf = natif * taux_source / taux_ptf
    arguments: { native_column: mt_ast, rate_column: xrt_rate_pos, pivot_rate_column: xrt_rate_ptf }

# ranges — package dbt_expectations
- dbt_expectations.expect_column_values_to_be_between:
    arguments: { min_value: 0 }                      # qt_ast >= 0
- dbt_expectations.expect_column_pair_values_A_to_be_greater_than_B:
    arguments: { column_A: dt_val, column_B: dt_exe, or_equal: true }
```

**Q1. "Tu as combien de tests dans ce projet et comment tu les
organises ?"**

*"Un peu plus de 600 tests dbt, répartis en trois familles qui répondent à
des questions différentes. Les tests structurels — `not_null`, `unique`,
`accepted_values`, `relationships` — répondent à 'est-ce que la donnée est
bien formée et référentiellement cohérente'. Les tests de cohérence — deux
macros custom que j'ai écrites, une pour la conversion directe vers CHF,
une pour la conversion pivot via le portefeuille — répondent à 'est-ce que
le calcul est mathématiquement exact', pas juste 'est-ce que la colonne
est remplie'. Et les tests de ranges, avec le package `dbt_expectations` —
poids bornés entre 0 et 1, taux strictement positifs, cohérence de dates
entre elles — répondent à 'est-ce que la valeur est plausible métier',
même si elle est non nulle et bien typée. Les trois sont complémentaires :
un montant peut être not-null et dans un range plausible tout en étant
faux si la conversion est cassée — d'où la deuxième famille."*

**Q2. "`accepted_values` sur une colonne à liste fermée, quelle est la
limite de cette approche ? Tu as un exemple où ça t'a posé problème ?"**

*"Oui, exactement ce cas. J'avais mis `accepted_values: ['PRIVATE',
'RETAIL']` sur la catégorie client dans `stg_cli`, sans savoir que le
référentiel réel (`stg_cli_cat`) en contenait quatre — `PRIVATE`,
`RETAIL`, `INSTIT`, `CORPOR`. Le test passait quand même, parce qu'aucun
client du jeu de démo n'utilisait les deux valeurs manquantes — un faux
négatif silencieux : le test donnait une fausse impression de couverture.
Le vrai problème avec une liste en dur, c'est qu'elle duplique le
référentiel et peut diverger sans que personne ne s'en aperçoive. Je l'ai
remplacée par un test `relationships` vers `stg_cli_cat.cd_cli_cat` — la
vérification devient 'est-ce que cette valeur existe dans le référentiel',
et elle reste juste même si le référentiel s'enrichit d'une cinquième
catégorie demain, sans toucher au code."*

**Q3. "Et sur le référentiel lui-même, `stg_cli_cat.cd_cli_cat`, tu mets
un `accepted_values` pour verrouiller les 4 valeurs connues ?"**

*"Non, volontairement. Un référentiel est justement l'endroit censé
accueillir une nouvelle valeur métier sans modification de code — une
nouvelle catégorie client, un nouveau groupe d'instruments. Y figer une
liste en dur recréerait exactement le problème que je viens de corriger
côté aval : chaque nouvelle valeur légitime casserait le pipeline jusqu'à
une modif de code, alors que c'est justement une simple donnée qui
devrait pouvoir arriver. Je garde juste `not_null` et `unique` sur le
référentiel, et je reporte la protection sur les tables qui le
référencent, via `relationships` — c'est là que je veux détecter une
vraie anomalie, un code orphelin qui ne correspond à rien de connu."*

---

### Comment fonctionne une macro de test custom (`{% test %}`)

**À quoi ça sert.** `{% test nom(model, column_name, ...) %}` déclare un
test générique réutilisable : dbt le compile en une macro `test_nom`,
injecte automatiquement `model` (le modèle testé) et `column_name` (la
colonne sous laquelle le test est déclaré en YAML), et le corps doit
retourner les lignes en échec — le test réussit si la requête ne retourne
aucune ligne.

**Mon code.**
```sql
-- tests/generic/test_currency_conversion_consistency.sql
{% test currency_conversion_consistency(model, column_name, native_column, rate_column, tolerance=0.01) %}

select
    *,
    {{ native_column }} * {{ rate_column }} as expected_{{ column_name }},
    abs({{ column_name }} - ({{ native_column }} * {{ rate_column }})) as ecart
from {{ model }}
where abs({{ column_name }} - ({{ native_column }} * {{ rate_column }})) > {{ tolerance }}

{% endtest %}
```
Appelé en YAML :
```yaml
- name: mt_net_ref
  tests:
    - currency_conversion_consistency:
        arguments:
          native_column: mt_net
          rate_column: xrt_rate
```

**Q1. "Comment dbt sait quel modèle et quelle colonne passer à ta macro de
test ? Tu ne les vois nulle part dans l'appel YAML."**

*"C'est le contrat implicite de `{% test %}` : `model` et `column_name`
sont toujours les deux premiers paramètres, et dbt les injecte lui-même à
partir du contexte — le modèle sous lequel le test est déclaré dans le
`schema.yml`, et le nom de la colonne juste au-dessus du `tests:`. Je n'ai
donc à fournir explicitement, sous `arguments:`, que les paramètres propres
à ma logique — ici `native_column` et `rate_column`. Ça me permet
d'attacher le même test à n'importe quelle paire colonne
native/convertie, sur n'importe quel modèle, sans dupliquer le SQL du test
lui-même."*

**Q2. "Pourquoi `arguments:` imbriqué et pas les paramètres directement
sous `currency_conversion_consistency:` ?"**

*"C'est la syntaxe dbt à jour — historiquement on pouvait mettre les
paramètres directement, mais dbt a introduit une dépréciation dessus :
sans `arguments:` imbriqué, j'avais un warning explicite au premier run,
`MissingArgumentsPropertyInGenericTestDeprecation`. Je l'ai corrigé tout
de suite pour rester compatible avec les futures versions de dbt, plutôt
que d'attendre que ça devienne une erreur bloquante."*

**Q3. "Tu as deux macros de test très proches, `currency_conversion_consistency`
et `currency_pivot_conversion_consistency`. Pourquoi pas une seule avec un
paramètre optionnel qui change la formule ?"**

*"J'ai hésité entre les deux options avant d'écrire le code : soit une
macro avec un paramètre optionnel `pivot_rate_column`, qui bifurque en
interne selon qu'il est fourni ou non, soit deux macros séparées. J'ai
choisi deux macros séparées pour ne pas toucher à une macro déjà écrite et
déjà validée par 78 tests verts au moment où j'ai eu besoin de la variante
pivot — une branche conditionnelle dans une macro qui marche déjà, c'est
un risque de régression pour un gain de réutilisation assez faible ici,
vu que les deux formules sont fondamentalement différentes (un taux
contre deux taux avec une division). Séparer les deux garde chaque macro
lisible et testable indépendamment."*

---

## MACROS

### À quoi sert une macro

**À quoi ça sert.** Une macro Jinja factorise un bloc de SQL réutilisable —
une expression, une clause, ou un select complet — pour ne pas dupliquer la
même logique à plusieurs endroits et risquer une divergence silencieuse.

**Mon code (macro d'expression simple).**
```sql
-- macros/safe_divide.sql
{% macro safe_divide(numerator, denominator) %}
    case
        when {{ denominator }} = 0 or {{ denominator }} is null
        then null
        else {{ numerator }} / {{ denominator }}
    end
{% endmacro %}
```

**Mon code (macro plus riche, avec composition de macros).**
```sql
-- macros/ytd_variation.sql
{% macro ytd_variation_pct(current_amount, start_amount) %}
    case
        when {{ start_amount }} is null or {{ start_amount }} = 0 then 0
        else (({{ current_amount }} - {{ start_amount }}) / {{ start_amount }}) * 100
    end
{% endmacro %}

{% macro ytd_start_lookup(daily_relation, partition_by, date_column, amount_column, calendar_relation) %}
select
    base.*,
    ytd_start.{{ amount_column }} as {{ amount_column }}_ytd_start,
    {{ ytd_variation_pct('base.' ~ amount_column, 'ytd_start.' ~ amount_column) }} as {{ amount_column }}_ytd_variation_pct
from {{ daily_relation }} as base
left join {{ daily_relation }} as ytd_start
    on {% for col in partition_by %}base.{{ col }} = ytd_start.{{ col }}{% if not loop.last %} and {% endif %}{% endfor %}
    and ytd_start.{{ date_column }} = (
        select min({{ date_column }}) from {{ calendar_relation }}
        where extract(year from {{ date_column }}) = extract(year from base.{{ date_column }})
    )
{% endmacro %}
```

**Q1. "`ytd_variation_pct` est appelée depuis `ytd_start_lookup`. Pourquoi
découper en deux macros plutôt qu'une seule ?"**

*"Parce que deux marts ont besoin de cette logique YTD à deux
granularités différentes : `mart_aum_ytd` par client/portefeuille,
`mart_rm_performance` par manager, après avoir sommé les montants. Le
self-join qui retrouve la première date de l'année — `ytd_start_lookup` —
n'a de sens qu'à la granularité client/portefeuille, une seule fois. Mais
la formule de variation en pourcentage, elle, doit être réappliquée une
deuxième fois après l'agrégation par manager, sur des montants déjà
sommés — donc sans refaire le self-join. En sortant `ytd_variation_pct`
dans sa propre macro, je peux l'appeler seule au niveau manager, et
`ytd_start_lookup` l'appelle aussi en interne pour le niveau
client/portefeuille. Résultat : la formule de variation n'existe qu'à un
seul endroit dans tout le projet, utilisée trois fois."*

**Q2. "Le `{% for col in partition_by %}` dans `ytd_start_lookup`, à quoi
ça sert exactement, et pourquoi c'est passé en paramètre plutôt qu'écrit en
dur ?"**

*"Ça génère dynamiquement la clause `ON` du self-join à partir d'une liste
de colonnes de granularité — `['cd_cli', 'cd_ptf']` par exemple — pour que
la même macro serve à n'importe quelle granularité sans dupliquer le code
de jointure. Si je l'avais écrit en dur avec `cd_cli` et `cd_ptf`
directement dans la macro, elle ne marcherait que pour cette granularité
précise ; en la passant en paramètre, la macro reste générique et
pourrait, en théorie, servir demain pour une agrégation YTD à une autre
granularité, sans y retoucher."*

**Q3. "Quelle est la différence structurelle entre une macro classique et
un test générique `{% test %}`, puisque les deux commencent par un mot-clé
Jinja et produisent du SQL ?"**

*"Un test `{% test %}` est en réalité compilé par dbt en une macro nommée
`test_<nom>` — donc techniquement c'est une macro, avec une convention en
plus : ses deux premiers paramètres, `model` et `column_name`, sont
toujours injectés automatiquement par dbt à partir du contexte YAML, et le
corps est censé retourner les lignes en échec pour que dbt sache si le
test passe ou non. Une macro `{% macro %}` classique n'a aucune convention
de ce genre : elle reçoit exactement les paramètres que je lui donne, et
elle peut retourner n'importe quel fragment SQL — une expression, une
clause de jointure, un `select` complet — appelé n'importe où dans un
modèle, pas seulement sous un `tests:` en YAML."*

---

## ARCHITECTURE

### Les 4 couches, la règle de dépendance stricte, et le check CI

**À quoi ça sert.** `st0 (seeds) → staging → intermediate → marts`, chaque
couche ne référence que la précédente — ça garde le debug simple : une
couche a une responsabilité unique et prévisible, jamais de court-circuit.

**Le problème.** Rien dans dbt ne vérifie ça nativement. Un mart qui lit un
modèle staging directement, en sautant l'intermediate, **compile et passe
tous les tests** sans que personne ne le voie.

**Mon code (le check que j'ai écrit).**
```python
# scripts/check_layer_dependencies.py
ALLOWED_DEPENDENCY_KINDS = {
    "staging": {"source", "seed"},
    "intermediate": {"staging", "snapshot"},
    "marts": {"intermediate"},
}
```
Le script lit `target/manifest.json`, déduit la couche de chaque modèle via
son `original_file_path`, classe chaque dépendance (`depends_on.nodes`) et
compare à la table ci-dessus. Intégré dans `dbt_ci.yml` juste après `dbt
run`, avant `dbt test` — exit 1 si violation, le CI passe au rouge.

**Q1. "Comment tu garantis que cette règle de couche est vraiment
respectée, pas juste documentée ?"**

*"En l'écrivant en dur dans `CLAUDE.md`, ça reste une convention qu'on peut
violer par erreur sans le savoir — c'est exactement ce qui s'est passé :
deux violations réelles dormaient dans le projet, `mart_aum_ytd` qui
lisait un `stg_*` directement, et un mart qui en lisait un autre. J'ai
écrit un script qui lit le manifest dbt, classe chaque modèle par couche à
partir de son chemin de fichier, et vérifie que chaque dépendance
appartient à une couche autorisée. Il tourne en CI juste après le build,
avant les tests de données — donc une violation de couche fait échouer le
pipeline avant même de vérifier si les chiffres sont justes, ce qui a plus
de sens : l'architecture est une précondition, pas un test parmi
d'autres."*

**Q2. "Pourquoi lire `manifest.json` plutôt que parser le SQL des modèles
toi-même pour trouver les `ref()` ?"**

*"Parce que dbt a déjà fait ce travail — le manifest contient le graphe de
dépendances résolu, `depends_on.nodes`, avec le type de chaque nœud
(modèle, source, seed, snapshot) et son `original_file_path`. Reparser le
Jinja moi-même pour retrouver les `ref()`/`source()` serait fragile — il
faudrait gérer les macros qui génèrent du SQL dynamiquement, les
conditions `{% if %}`, etc. — et redondant, puisque dbt l'a déjà résolu à
la compilation. Le manifest est la source de vérité une fois `dbt compile`
ou `dbt run` exécuté ; mon script n'a plus qu'à appliquer une règle de
classification dessus."*

**Q3. "Ton script tourne après `dbt run`, pas après `dbt compile`. Pourquoi
pas juste un `dbt compile`, qui est plus rapide et suffit à générer le
manifest ?"**

*"Dans mon CI actuel, `dbt run` était déjà l'étape qui existait juste
avant, donc le manifest était de toute façon frais à ce moment-là — ajouter
le check juste après ne coûte rien de plus. Un `dbt compile` seul aurait
suffi pour la vérification de dépendances en tant que telle, puisque le
graphe est connu dès la compilation sans exécuter le SQL. Mais dans mon
pipeline, `dbt run` doit de toute façon tourner avant `dbt test` pour que
les tables existent — donc autant vérifier l'architecture juste après,
avant de lancer des tests de données sur un pipeline potentiellement mal
architecturé."*

**Anecdote à raconter si on pousse plus loin — "pourquoi une macro et pas
un modèle intermediate".** *"En corrigeant ces deux violations, ma première
idée était de créer un modèle `int_aum` pour partager le calcul d'AUM entre
les deux marts. Mais ce modèle aurait dû lire `int_fct_ast`, `int_cli`,
`int_ptf` — trois autres modèles intermediate — ce qui est exactement le
cas `int_* → int_*` que `CLAUDE.md` interdit explicitement, et qu'aucun
modèle intermediate du projet ne fait aujourd'hui. Mon propre script de
vérification me l'a confirmé : 0 violation avant, 4 nouvelles après avec
`int_aum`. La bonne solution n'était pas un modèle mais une macro — une
macro n'est pas un nœud du graphe de dépendances, donc la partager entre
deux marts ne crée aucune arête et ne viole aucune règle de couche. C'est
devenu `ytd_start_lookup`."*

**Piège classique — "et mart→mart, c'est autorisé chez toi ?"** *"Non,
volontairement interdit, alors que `CLAUDE.md` ne l'interdisait pas
explicitement au départ — seulement `int_*→int_*` et `mart_*→stg_*`. J'ai
tranché pour l'interdire aussi, parce que la raison d'être de la règle
('garder le debug simple, une responsabilité par couche') s'applique à
l'identique aux marts : si je l'autorisais, `mart_rm_performance` qui lisait
`mart_aum_ytd` serait resté légal, mais ça aurait ouvert la porte à des
chaînes de marts de plus en plus profondes avec le temps."*

---

## MULTI-DEVISES

### Natif / `_ptf` / `_ref`, le pivot CHF, taux daté

**À quoi ça sert.** Chaque montant financier existe sur trois axes : natif
(devise de la position/opération), `_ptf` (converti en devise du
portefeuille), `_ref` (converti en CHF, devise de référence banque) — pour
qu'un client CHF voie tous ses portefeuilles consolidés, quelle que soit
leur devise locale.

**Pourquoi un pivot et pas un taux croisé direct.** Le référentiel de taux
(`stg_fct_xrt`) ne contient que des taux **vers CHF**, pas toutes les paires
croisées possibles (USD→EUR, EUR→GBP...). Convertir une position USD vers
un portefeuille en EUR passe donc par CHF comme intermédiaire : `natif ×
taux_position→CHF ÷ taux_portefeuille→CHF`.

**Mon code.**
```sql
-- models/intermediate/int_fct_ast.sql
coalesce(xrt_pos.rt_val, 1) as xrt_rate_pos,
coalesce(xrt_ptf.rt_val, 1) as xrt_rate_ptf,

-- _ptf : pivot CHF (deux taux)
cast(fct_ast.mt_ast * coalesce(xrt_pos.rt_val, 1)
     / coalesce(xrt_ptf.rt_val, 1) as decimal(19,4)) as mt_ast_ptf,

-- _ref : conversion directe vers CHF (un seul taux)
cast(fct_ast.mt_ast * coalesce(xrt_pos.rt_val, 1) as decimal(19,4)) as mt_ast_ref,
```
Taux **daté** — jamais un taux fixe, toujours celui le plus récent à la date
du fait (ou avant, si le marché était fermé) :
```sql
-- models/intermediate/int_fct_ptf.sql
left join xrt xrt_ptf
    on ptf.cd_ccy = xrt_ptf.cd_ccy
    and xrt_ptf.dt_fct = (
        select max(x2.dt_fct)
        from {{ ref('stg_fct_xrt') }} x2
        where x2.cd_ccy = ptf.cd_ccy
          and x2.dt_fct <= fct_ptf.dt_fct
    )
```

**Q1. "Pourquoi le staging n'a jamais le droit de faire cette conversion,
uniquement l'intermediate ?"**

*"Parce que le staging expose la donnée brute dans sa devise native,
point — c'est une règle absolue du projet, sans colonne `_ptf` ou `_ref`
autorisée à cette couche. La conversion a besoin de croiser deux sources
différentes : le fait lui-même et le référentiel de taux, daté à la date
du fait, pas un taux fixe — c'est déjà une logique métier d'enrichissement,
exactement la responsabilité de l'intermediate. Mélanger ça dans le
staging casserait la règle de couche, et rendrait impossible de
distinguer 'la donnée telle qu'extraite' de 'la donnée après logique
métier' en cas de bug de conversion. Et cette cohérence — `_ref = natif ×
taux`, `_ptf = natif × taux_source ÷ taux_portefeuille` — n'est pas juste
crue sur parole : 35 tests `currency_conversion_consistency` /
`currency_pivot_conversion_consistency` la vérifient à chaque run, sur les
4 modèles de faits intermediate."*

**Q2. "Pourquoi `coalesce(xrt_pos.rt_val, 1)` — un taux à 1 par défaut ?
Ça ne fausse pas les montants si le taux est vraiment manquant ?"**

*"C'est un choix de robustesse plutôt que de silence total : si aucun
taux n'est trouvé pour une devise/date — jointure externe `left join` qui
ne matche rien — je préfère que le montant converti soit égal au montant
natif (facteur 1) plutôt qu'une valeur nulle qui casserait des agrégations
en aval (`sum()` sur du null). Mais je suis conscient que c'est un choix
qui peut masquer un vrai problème de données manquantes dans le
référentiel de taux — c'est un compromis, pas une solution parfaite. Dans
un vrai run de production, je m'attendrais à ce qu'un taux manquant soit
rare et signalé autrement, par exemple via un test de fraîcheur ou de
complétude sur `stg_fct_xrt` lui-même."*

**Q3. "Le taux est cherché avec `max(dt_fct) <= date du fait`, pas une
égalité stricte. Pourquoi ?"**

*"Parce que le marché n'est pas ouvert tous les jours — week-ends, jours
fériés — donc un taux de change n'existe pas forcément exactement à la
date du fait. En prenant le taux le plus récent disponible à cette date
ou avant, je m'assure d'avoir toujours une valeur, plutôt que de perdre la
conversion les jours sans cotation. C'est une sous-requête corrélée : pour
chaque ligne de fait, elle cherche la date de taux maximale antérieure ou
égale — le prix à payer, documenté dans mes notes de scaling, c'est que
sur un très gros volume ça devient un scan à chaque ligne, à optimiser
avec un vrai calendrier de marché ou une jointure asof si le volume
grossit."*

---

## CI/CD & OUTILLAGE

### Le pipeline CI (`dbt_ci.yml`)

**À quoi ça sert.** Reproduire l'ordre d'exécution obligatoire du projet à
chaque push/PR sur `main`, sur une base DuckDB éphémère, pour détecter
toute régression avant merge.

**Mon code.**
```yaml
# .github/workflows/dbt_ci.yml (ordre des étapes)
- DBT Deps
- DBT Seed            # --full-refresh
- DBT Run Staging     # dbt run --select staging
- DBT Snapshot
- DBT Run             # dbt run (tout, y compris staging une 2e fois)
- Check layer dependencies   # scripts/check_layer_dependencies.py
- DBT Test
```

**Q1. "Pourquoi `dbt run --select staging` ET un `dbt run` complet juste
après ? Ça ne rebuild pas deux fois le staging pour rien ?"**

*"Si, exactement — et c'est ce qui a causé l'incident `stg_set_cal` : le
staging est bien reconstruit deux fois dans le même pipeline. La raison
d'être de cette redondance, c'est l'ordre imposé par `CLAUDE.md` : le
staging doit être construit avant les snapshots (qui lisent `stg_cli` /
`stg_ptf`), qui doivent être construits avant l'intermediate. Le `dbt run`
complet ensuite couvre intermediate et marts, mais comme il n'exclut pas
`--select staging+`, il retraite le staging par la même occasion. Ce
n'est pas optimal — je pourrais faire `dbt run --exclude staging` sur la
dernière étape — mais je ne l'ai pas changé volontairement : ça reste un
bon test de robustesse, ça prouve que mes modèles incrémentaux tiennent
un deuxième passage consécutif sans dupliquer, ce qui a justement permis
de révéler le bug plutôt que de le cacher."*

**Q2. "Le check de dépendances de couche est placé où dans ce pipeline, et
pourquoi cet ordre précis ?"**

*"Juste après `dbt run`, avant `dbt test`. Le manifest est frais à ce
moment (`dbt run` vient de le régénérer), et je préfère échouer sur une
violation d'architecture avant de dépenser du temps sur des centaines de
tests de données — si l'architecture est cassée, la valeur des tests de
données qui suivent est discutable de toute façon."*

---

### Le hook de validation YAML (`.claude/settings.json`)

**À quoi ça sert.** Un hook `PostToolUse` qui valide chaque `.yml`/`.yaml`
édité par l'agent IA (Claude Code) avant de continuer — attrape des bugs
YAML que ni un parseur standard ni `dbt parse` ne détectent.

**Mon code (les deux checks qui font le vrai travail).**
```python
# .claude/hooks/validate_yaml.py
class UniqueKeyLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise ValueError(f"duplicate key {key!r}")
            seen.add(key)
        return super().construct_mapping(node, deep)
```

**Q1. "Pourquoi pas juste `yaml.safe_load()` standard, qui existe déjà en
Python ?"**

*"Parce que je l'ai testé empiriquement avant de l'écrire, et il ne
suffit pas. Le spec YAML autorise les clés dupliquées dans un mapping —
`yaml.safe_load` garde silencieusement la dernière valeur sans lever
d'erreur. C'est exactement ce qui s'est produit une fois dans ce projet :
un bloc `tests:` dupliqué sous une même colonne a fait disparaître
silencieusement un test `unique` — le premier bloc `tests:` a juste été
écrasé par le second. J'ai écrit un loader custom qui surcharge
`construct_mapping` pour lever une erreur explicite sur une clé
dupliquée, au lieu de la tolérer."*

**Q2. "Tu as un deuxième check en plus de la détection de clé dupliquée.
Il sert à quoi ?"**

*"Il détecte un cas encore plus insidieux : une indentation cassée qui
reste **syntaxiquement valide** en YAML, mais qui fait glisser l'entrée
d'un modèle dans la liste `columns:` du modèle précédent — donc ce
modèle perd silencieusement toute sa documentation et ses tests, sans
aucune erreur de parsing, et `dbt parse` ne le détecte pas non plus, je
l'ai vérifié en le reproduisant volontairement. Mon check vérifie qu'une
entrée sous `columns:` ne contient que des clés de colonne valides
(`name`, `description`, `tests`...), jamais des clés réservées au niveau
modèle comme `columns` ou `config` — si c'est le cas, c'est la signature
d'un modèle avalé par la mauvaise liste parente."*

**Q3. "Et `dbt parse`, tu le gardes quand même en troisième étape alors
qu'il ne détecte ni l'un ni l'autre cas — pourquoi ?"**

*"Parce qu'il attrape autre chose : une vraie casse de syntaxe Jinja, une
indentation qui casse complètement le YAML (pas juste le glisse
silencieux), une config invalide. Ce n'est pas suffisant seul, mais ce
n'est pas inutile non plus — les trois checks se complètent, chacun
couvrant un angle mort différent des deux autres."*

---

## SECRETS & CONFIGURATION

### `profiles.yml` et `env_var()`

**À quoi ça sert.** Séparer la configuration de connexion (dev/prod, type
d'entrepôt) du code versionné, et ne jamais committer de secret en clair.

**Mon code.**
```yaml
# ~/.dbt/profiles.yml (hors repo, jamais versionné)
banking_pipeline:
  outputs:
    dev:
      type: duckdb
      path: dev.duckdb
      threads: 1
    prod:
      type: snowflake
      account: "{{ env_var('DBT_SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('DBT_SNOWFLAKE_USER') }}"
      password: "{{ env_var('DBT_SNOWFLAKE_PASSWORD') }}"
      role: "{{ env_var('DBT_SNOWFLAKE_ROLE') }}"
      database: "{{ env_var('DBT_SNOWFLAKE_DATABASE') }}"
      warehouse: "{{ env_var('DBT_SNOWFLAKE_WAREHOUSE') }}"
      schema: "{{ env_var('DBT_SNOWFLAKE_SCHEMA') }}"
      threads: 4
  target: dev
```

**Q1. "Pourquoi `profiles.yml` n'est jamais dans le repo ?"**

*"Parce qu'il contient soit des identifiants de connexion, soit — comme
ici avant correction — carrément un mot de passe en clair. `CLAUDE.md`
l'interdit explicitement, et `.gitignore` l'exclut. Le repo contient le
code (les modèles, les tests), pas les moyens d'accès aux entrepôts —
chaque développeur ou environnement CI a son propre `profiles.yml` local,
qui pointe le même nom de profil (`banking_pipeline`) vers des cibles
différentes selon où il tourne."*

**Q2. "Concrètement, j'ai trouvé un mot de passe Snowflake en clair dans
ton profil local pendant cette session. Comment tu l'as corrigé ?"**

*"Je l'ai remplacé par des appels `env_var()` sur les 7 champs sensibles —
compte, user, password, rôle, base, warehouse, schéma — et j'ai documenté
les variables d'environnement à exporter dans le shell, hors de tout
fichier versionné. `env_var()` est une fonction Jinja de dbt qui lit une
variable d'environnement au moment de la résolution du profil ; si elle
n'est pas définie, dbt échoue explicitement au lieu de se connecter avec
une valeur vide. Le fichier profile lui-même reste hors repo comme avant,
mais même localement il ne contient plus de secret en clair — si jamais
ce fichier fuitait par un autre biais (backup, partage d'écran), le
secret ne serait pas dedans."*

---

## PASSAGE À L'ÉCHELLE (si on te pousse sur la prod)

Cette section résume `docs/scaling.md`, que j'ai écrit dans le projet —
citer son existence en entretien montre que la réflexion "prod" a été
faite consciemment, pas improvisée sur place.

**Q1. "Ce projet tourne sur une démo de quelques dizaines de lignes.
Qu'est-ce qui casserait en premier à un vrai volume bancaire ?"**

*"Le premier point, c'est le `NOT IN (subquery)` que j'utilise pour filtrer
les nouvelles lignes dans les 4 faits intermediate. Sur onze lignes c'est
instantané ; sur des dizaines de millions de positions historisées, c'est
un scan complet de la clé métier à chaque run, sans aucun pruning possible
— contrairement à un filtre sur une colonne de date, qui peut s'appuyer
sur le clustering. Le deuxième point, c'est mon pattern
`MAX(id)+row_number()` pour les ID de dimension : `MAX()` sur la table
cible entière est un point de sérialisation, ça ne passe pas bien si deux
chargements de dimensions tournent en parallèle. Je documente les deux
dans `docs/scaling.md`, avec les évolutions concrètes : filtrage par date
pour le premier, `dbt_utils.generate_surrogate_key` — un hash du code
métier, calculable indépendamment sans lire la table cible — pour le
second."*

**Q2. "Le `cluster_by` que tu as mis sur les marts, il sert à quoi
exactement sur Snowflake, et est-ce que tu l'as testé ?"**

*"`cluster_by` demande à Snowflake de trier physiquement les données par
micro-partition selon les colonnes indiquées — ici la date en premier,
puis la dimension la plus filtrée par le BI (client, portefeuille, ou
manager selon le mart). Ça permet l'élimination de micro-partitions
entières sur une requête filtrée par date, sans les lire. Honnêtement non,
je ne l'ai jamais vu s'exécuter réellement : `cluster_by` est un no-op
silencieux sur DuckDB, seul l'adaptateur Snowflake le traduit en vrai
`CLUSTER BY`, et ce projet tourne en local sur DuckDB. C'est un point que
j'assume et documente comme limite : la config est là, avec le bon
raisonnement, mais jamais validée en conditions réelles faute d'accès à
un vrai warehouse Snowflake avec assez de volume pour que le clustering se
déclenche."*

**Q3. "Ton DAG Airflow est une chaîne linéaire de `BashOperator`. Comment
tu le ferais évoluer à l'échelle ?"**

*"Aujourd'hui chaque étape appelle `dbt run --select <couche>` en bloc,
donc Airflow ne voit qu'une tâche par couche — toute la parallélisation
possible entre modèles indépendants d'une même couche est invisible pour
lui, déléguée uniquement à `--threads` côté dbt. À l'échelle, je
génèrerais les tâches Airflow directement depuis `manifest.json` — avec un
outil comme Cosmos, cohérent avec l'usage d'Astronomer déjà en place — pour
qu'Airflow pilote le vrai graphe de dépendances dbt, avec parallélisation
automatique et un retry au niveau du modèle qui a échoué, pas de toute la
couche."*

---

# FLASH QUICKFIRE — révision de dernière minute

Question courte → réponse en une phrase. À parcourir juste avant
l'entretien, sans relire les explications complètes.

- **`ref()` vs `source()` ?** → `source()` seulement en staging (donnée
  brute), `ref()` partout ailleurs (lineage + indépendance d'environnement).
- **Pourquoi `view`/`table`/`incremental` à ces 3 endroits précis ?** →
  view = intermediate (pas cher à recalculer), table = marts (lu souvent
  par le BI), incremental = staging + faits intermediate (source qui
  grossit indéfiniment).
- **Rôle des seeds ici ?** → simuler l'extraction Avaloq sans vraie
  connexion ; migrer vers une vraie source ne changerait que
  `sources.yml`, pas le SQL.
- **`unique_key` sert à quoi ?** → dit à dbt de merger (upsert) au lieu
  d'append pur sur un modèle incrémental.
- **Pattern `MAX(id)+row_number()` ?** → ID technique stable : les lignes
  connues gardent leur ID via `existing`, les nouvelles reçoivent
  `MAX+row_number` calculé seulement sur le nouveau lot.
- **Incident `stg_set_cal` en une phrase ?** → incrémental sans
  `unique_key` → append pur → calendrier dupliqué à chaque run,
  invisible jusqu'à l'ajout d'un test `unique` sur `dt_fct`.
- **Snapshot SCD2, à quoi bon ?** → dbt gère la logique de clôture/ouverture
  de version à ma place, via `dbt_valid_from`/`dbt_valid_to`, réutilisés
  ensuite par `int_cli`/`int_ptf` pour produire un état daté.
- **`timestamp` vs `check` en stratégie de snapshot ?** → `timestamp` si
  une colonne avance de façon fiable (`ts_stg`) ; `check` sinon, plus
  coûteux (compare les colonnes une à une).
- **3 familles de tests ?** → structurels (bien formé), cohérence (calcul
  juste, mes macros currency_*), ranges (plausible métier, dbt_expectations).
- **Générique vs singulier ?** → générique si réutilisable sur plusieurs
  colonnes/modèles, singulier pour une règle métier locale à un seul
  modèle.
- **`{% test %}` reçoit quels paramètres automatiquement ?** → `model` et
  `column_name`, injectés par dbt depuis le contexte YAML.
- **Pourquoi `relationships` plutôt que `accepted_values` sur `cd_cli_cat` ?**
  → une liste en dur duplique le référentiel et dérive silencieusement ;
  `relationships` s'auto-maintient.
- **Pourquoi pas `accepted_values` sur le référentiel lui-même ?** → un
  référentiel doit pouvoir accueillir une nouvelle valeur sans modif de
  code.
- **Macro vs test générique, différence structurelle ?** → un test est
  une macro compilée `test_<nom>` avec `model`/`column_name` injectés
  automatiquement ; une macro classique ne reçoit que ce qu'on lui passe.
- **Pourquoi 2 macros pour le YTD (`ytd_start_lookup` +
  `ytd_variation_pct`) ?** → 2 granularités différentes (client/portefeuille
  vs manager) ; la formule de variation doit être réutilisable sans
  refaire le self-join.
- **La règle de dépendance stricte entre couches ?** → chaque couche ne lit
  que la précédente ; rien dans dbt ne le vérifie, d'où
  `check_layer_dependencies.py` en CI juste après `dbt run`.
- **Pourquoi `int_aum` abandonné ?** → aurait dû lire 3 autres modèles
  intermediate (`int_* → int_*` interdit) ; remplacé par une macro, qui ne
  crée aucune arête dans le graphe.
- **Mart→mart, autorisé ?** → non, tranché volontairement même si pas
  explicitement interdit au départ, pour la même raison que int→int.
- **Pourquoi le pivot CHF pour `_ptf` ?** → le référentiel de taux ne
  connaît que les taux vers CHF, pas les paires croisées directes.
- **Pourquoi le taux est "daté" (`<=` pas `=`) ?** → le marché n'est pas
  ouvert tous les jours, on prend le taux le plus récent disponible.
- **Pourquoi le staging n'a jamais de `_ptf`/`_ref` ?** → conversion =
  logique métier = responsabilité de l'intermediate, jamais du staging.
- **Comment la conversion est validée, pas juste crue sur parole ?** → 35
  tests `currency_conversion_consistency`/`currency_pivot_conversion_consistency`.
- **CI : pourquoi staging construit deux fois ?** → ordre imposé
  (staging avant snapshot avant intermediate), le `dbt run` final ne
  l'exclut pas — ce qui a justement révélé l'incident `stg_set_cal`.
- **Pourquoi un hook YAML custom plutôt que `yaml.safe_load` seul ?** →
  YAML autorise les clés dupliquées silencieusement (bug réel vécu), et
  ni lui ni `dbt parse` ne détectent un modèle avalé par la mauvaise
  liste parente.
- **Comment les secrets Snowflake sont gérés ?** → `env_var()` dans
  `profiles.yml`, jamais de valeur en clair, fichier lui-même hors repo.
- **Le plus gros risque à l'échelle selon toi ?** → le `NOT IN` sur clé
  métier (scan complet, non sargable) et le `MAX(id)` de génération d'ID
  (point de sérialisation) — les deux documentés avec leur évolution dans
  `docs/scaling.md`.
