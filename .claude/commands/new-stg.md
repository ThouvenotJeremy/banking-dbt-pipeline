---
description: Génère un nouveau modèle staging dbt (stg_*) conforme aux conventions du projet, à partir d'une table source st0_*
---

Tu vas créer un nouveau modèle de la couche **staging** pour la table source
`$ARGUMENTS` (ex: `st0_xxx`). Suis ce processus dans l'ordre, sans sauter
d'étape.

## 1. Lire les conventions

Lis `CLAUDE.md` à la racine du projet. Les règles qui suivent en sont un
résumé, mais `CLAUDE.md` fait autorité en cas de doute — notamment la règle
de dépendance stricte entre couches et la nomenclature des préfixes/suffixes.

## 2. Déterminer le type de table et choisir un modèle de référence

- Si le nom de la table source contient `fct` (ex: `st0_fct_xxx`) → c'est un
  **fait**, le modèle doit aller dans `models/staging/faits/` et s'appeler
  `stg_fct_<xxx>.sql`. Lis un modèle existant de ce dossier (ex:
  `stg_fct_ast.sql` ou `stg_fct_ope.sql`) comme référence de pattern.
- Sinon → c'est une **dimension**, le modèle doit aller dans
  `models/staging/dimensions/` et s'appeler `stg_<xxx>.sql`. Lis un modèle
  existant de ce dossier (ex: `stg_cli.sql`) comme référence de pattern.

Lis aussi `models/staging/faits/sources.yml` pour connaître la description
exacte et les colonnes de la table source `$ARGUMENTS` — ce fichier
référence **toutes** les tables `st0_*` (dimensions et faits confondus),
même si son chemin est sous `faits/`.

## 3. Générer le modèle `stg_*`

Le fichier SQL doit reproduire exactement le pattern du modèle de référence
lu à l'étape 2, avec pour la nouvelle table :

- `{{ config(materialized='incremental', unique_key='<code métier>') }}` —
  le `unique_key` est le code métier de la table (colonne `cd_*` qui
  identifie une ligne de façon unique dans la source).
- Toutes les métadonnées techniques obligatoires, dans cet ordre :
  - `id_stg_<table>` — id séquentiel stable, avec le pattern incrémental
    exact : en mode `is_incremental()`, conserver l'id existant pour les
    lignes déjà connues (jointure sur le code métier), et attribuer
    `MAX(id) + row_number()` uniquement aux nouvelles lignes (voir
    `stg_cli.sql` pour le CTE `existing` / `max_id` / `enriched`).
  - `ts_stg` — `current_timestamp`
  - `vr_stg` — `ts_stg` formaté en `YYYYMMDD`
  - `id_obj_tec` — identifiant numérique de l'objet technique. Regarde les
    valeurs déjà utilisées dans les autres modèles staging et les
    descriptions `id_obj_tec` du `schema.yml` correspondant pour choisir un
    identifiant qui ne soit pas déjà pris.
  - `cd_src` — nom de la table source (`'$ARGUMENTS'`)
  - `cd_pid` — `{{ invocation_id }}`
  - `lb_dsc` — `null` par défaut (sauf si le modèle de référence fait
    autrement)
- Toutes les colonnes métier de la source, castées comme dans le modèle de
  référence (types explicites sur les dates, décimaux, etc.).

**Rappel impératif :** aucune colonne `_ref` ni `_ptf` ne doit apparaître
dans ce modèle. Le staging expose uniquement la devise native de la source.
Ces conversions sont interdites ici — elles se font exclusivement en
intermediate.

## 4. Mettre à jour `sources.yml`

Ajoute l'entrée de la table `$ARGUMENTS` dans
`models/staging/faits/sources.yml`, sous `sources: st0: tables:`, avec une
`description` et la liste des `columns` (avec leur `description`), en
suivant le format des entrées existantes.

## 5. Mettre à jour le schema.yml

Ajoute l'entrée du modèle `stg_*` dans le fichier approprié :
- `models/staging/schema_dimensions.yml` pour une dimension
- `models/staging/schema_faits.yml` pour un fait

Suis exactement le format des entrées existantes : `description` du modèle,
`config.materialized: incremental`, puis chaque colonne avec sa
`description` et ses `tests` (`not_null`/`unique` sur `id_stg_*` et le code
métier au minimum, comme dans les modèles de référence).

## 6. Ne pas exécuter dbt

Crée uniquement les fichiers (le `.sql` et les modifications des deux
`.yml`). N'exécute **aucune** commande `dbt` (pas de `dbt run`, `dbt test`,
`dbt parse`, etc.). Termine en montrant à l'utilisateur :
- le chemin et le contenu du nouveau modèle `.sql`
- le diff des ajouts dans `sources.yml`
- le diff des ajouts dans le `schema.yml` concerné
