# CLAUDE.md — banking-dbt-pipeline

Règles à respecter pour contribuer à ce projet dbt. Ce fichier prime sur toute
initiative d'architecture personnelle.

## ARCHITECTURE

4 couches, avec des snapshots SCD2 entre staging et intermediate :

```
st0 (seeds) → staging → snapshots (SCD2) → intermediate → marts
```

**Règle de dépendance STRICTE, non négociable :** chaque couche ne référence
que la couche immédiatement précédente.

- `stg_*` lit `st0` (seeds/sources) uniquement
- `int_*` lit `stg_*` / les snapshots uniquement
- `mart_*` lit `int_*` uniquement

**Interdits absolus :**
- un modèle `int_*` qui `{{ ref() }}` un autre `int_*`
- un modèle `mart_*` qui `{{ ref() }}` un `stg_*` (en sautant l'intermediate)

Cette règle existe pour garder le debug simple : chaque couche a une
responsabilité unique et prévisible. Ne jamais la contourner pour "gagner du
temps" sur un modèle.

## NOMENCLATURE

### Préfixes de colonnes
| Préfixe | Signification |
|---|---|
| `cd_` | code métier |
| `lb_` | libellé |
| `mt_` | montant |
| `qt_` | quantité |
| `dt_` | date |
| `yn_` | booléen (O/N) |
| `rt_` | taux |
| `pc_` | pourcentage |
| `id_` | identifiant technique |
| `nb_` | nombre / séquence |

### Suffixes de devise (montants uniquement)
| Suffixe | Signification |
|---|---|
| *(aucun)* | devise native de la source |
| `_ptf` | converti en devise du portefeuille |
| `_ref` | converti en CHF (devise de référence banque) |

## COUCHE STAGING (`models/staging/`)

- Matérialisation `incremental`, deux sous-dossiers : `dimensions/` et `faits/`
- Métadonnées techniques obligatoires sur chaque modèle :
  - `id_stg_<table>` — id séquentiel stable entre les runs
  - `ts_stg` — timestamp de staging
  - `vr_stg` — version au format `YYYYMMDD`
  - `id_obj_tec` — id référentiel de l'objet technique
  - `cd_src` — nom de la source
  - `cd_pid` — `invocation_id` du run dbt
- **Pattern d'ID incrémental** (voir `stg_cli.sql` comme référence) :
  `unique_key` sur le code métier ; en mode incrémental, conserver l'id
  existant pour les lignes déjà connues, attribuer `MAX(id) + row_number()`
  uniquement aux nouvelles lignes.
- **Interdit dans staging :** aucune colonne `_ref` ni `_ptf`. Le staging est
  en devise native uniquement — la conversion se fait en intermediate.

## COUCHE INTERMEDIATE (`models/intermediate/`)

- C'est **ici** que sont calculées les colonnes `_ptf` et `_ref`, via
  jointure sur les taux de change datés (`stg_fct_xrt`), **au taux de la
  date du fait** — jamais un taux fixe.
- Conversion `_ptf` via pivot CHF : `montant * taux_source / taux_devise_ptf`
- L'historisation SCD2 (issue des snapshots) est croisée avec le calendrier
  `stg_set_cal` pour produire un état daté par jour.

## ORDRE D'EXÉCUTION (obligatoire)

```
seed → run staging → snapshot → run intermediate → run marts → test
```

Raison : le staging alimente les snapshots (qui lisent `stg_cli` / `stg_ptf`),
qui alimentent à leur tour l'intermediate. Ne jamais paralléliser ou inverser
ces étapes.

## COMMANDES

```bash
# Pipeline complet, base vierge, dans l'ordre obligatoire —
# ne jamais paralléliser ou inverser ces étapes

# dbt deps et dbt seed ne sont nécessaires qu'au premier run,
# ou après modification des packages / des fichiers seeds
dbt deps
dbt seed --full-refresh

dbt run --select staging
dbt snapshot
dbt run --select intermediate
dbt run --select marts
dbt test

# Build complet respectant l'ordre des couches (alternative)
dbt build

# Vérifier ce qu'un modèle référence / qui en dépend (avant toute modif)
dbt list --select <model_name>+
dbt list --select +<model_name>

# Docs
dbt docs generate && dbt docs serve
```

Profil local : DuckDB (`dev.duckdb`), cible prod : Snowflake. Ne jamais
committer `profiles.yml` ni `*.duckdb` (déjà exclus par `.gitignore`).

Le dossier `include/` à la racine est une copie du projet non versionnée
(exclue par `.gitignore`) — ne pas y éditer de fichiers, toujours travailler
à la racine du repo.
