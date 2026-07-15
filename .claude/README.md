# Workflow Claude Code — banking-dbt-pipeline

Ce dossier configure [Claude Code](https://claude.com/claude-code) comme
outil de développement sur ce projet dbt. Ce document explique ce qui est
en place et pourquoi.

## 1. `CLAUDE.md` — cadrer l'agent avec des règles explicites

À la racine du repo, `CLAUDE.md` est un fichier de règles **versionné**,
lu automatiquement par l'agent à chaque session. Il contient :

- la règle de dépendance stricte entre couches (`staging → snapshots →
  intermediate → marts`, chaque couche ne référence que la précédente,
  interdiction de sauter une couche ou de faire du `int_*` → `int_*`) ;
- la nomenclature des préfixes de colonnes (`cd_`, `lb_`, `mt_`, `dt_`,
  `yn_`, `rt_`, `pc_`, `id_`, `nb_`) et des suffixes de devise (`_ptf`,
  `_ref`) ;
- le pattern exact des métadonnées techniques obligatoires en staging
  (`id_stg_*`, `ts_stg`, `vr_stg`, `id_obj_tec`, `cd_src`, `cd_pid`) et
  l'algorithme d'ID incrémental associé ;
- l'ordre d'exécution obligatoire du pipeline (`seed → staging → snapshot
  → intermediate → marts → test`) et l'interdiction de le paralléliser.

**Pourquoi documenter ces règles au lieu de les garder implicites :**

Un agent sans contexte versionné réapprend l'architecture du projet à
chaque session en lisant le code — avec le risque d'halluciner un
raccourci (ex: un mart qui lit directement un staging) qui compile et
passe les tests dbt existants sans violer aucune contrainte SQL, mais
casse une convention métier invisible dans le schéma. `CLAUDE.md` rend
ces contraintes explicites et opposables : l'agent les relit à chaque
tâche, et un humain qui relit une PR générée peut vérifier le respect des
règles sans deviner l'intention. Le fichier est versionné avec le code
donc il évolue avec le projet — un renommage de préfixe ou une nouvelle
couche s'y reflète immédiatement pour toutes les sessions futures.

## 2. La slash command `/new-stg`

Définie dans `.claude/commands/new-stg.md`. Invocation :

```
/new-stg st0_pos_typ
```

**Ce qu'elle fait :** génère un nouveau modèle de la couche staging pour
une table source `st0_*`, en 6 étapes fixes :

1. relit `CLAUDE.md` pour les règles à jour ;
2. détermine si la table est un fait (`st0_fct_*` → `models/staging/faits/`,
   nommage `stg_fct_<xxx>.sql`) ou une dimension (→
   `models/staging/dimensions/`, nommage `stg_<xxx>.sql`), et choisit un
   modèle existant du même dossier comme référence de pattern ;
3. génère le `.sql` en reproduisant exactement ce pattern (config
   incrémentale, `unique_key` sur le code métier, CTE `existing` /
   `max_id` / `enriched` pour l'ID stable entre les runs, métadonnées
   techniques dans l'ordre imposé, aucune colonne `_ptf`/`_ref`) ;
4. ajoute l'entrée de la table source dans `sources.yml` ;
5. ajoute l'entrée du modèle avec ses tests dans le `schema.yml`
   correspondant ;
6. **n'exécute aucune commande dbt** — elle ne fait que créer/modifier des
   fichiers, et affiche le diff pour revue.

**Pourquoi elle existe :** ce projet a ~20 modèles staging qui suivent
tous le même squelette (mêmes 6 colonnes techniques, même algorithme
d'ID incrémental à base de `row_number()` + jointure sur le code
métier). Écrire ce squelette à la main pour chaque nouvelle table est
répétitif et propice à l'erreur de copier-coller silencieuse (un
`id_obj_tec` dupliqué, un `unique_key` qui ne correspond pas au vrai code
métier, une métadonnée oubliée). La commande fige le processus dans un
prompt versionné : le résultat est reproductible d'un contributeur à
l'autre et d'une session à l'autre, et le diff produit reste petit et
revuable — pas une réécriture de fichiers existants.

Exemple réel : `git log --oneline -- models/staging/dimensions/stg_pos_typ.sql`
montre le modèle `stg_pos_typ` généré par cette commande (type dimension,
car `st0_pos_typ` ne contient pas `fct`), avec `id_obj_tec = 1023` choisi
en vérifiant les valeurs déjà prises par les 22 autres modèles staging.

## 3. Workflow type d'un contributeur

1. **Analyser avant de modifier.** Avant de toucher un modèle, vérifier
   ses dépendances : `dbt list --select <model>+` (ce qui en dépend) et
   `dbt list --select +<model>` (ce dont il dépend). Ça évite de casser
   une couche en aval sans le savoir.
2. **Respecter l'ordre des couches.** Toute modification touchant
   plusieurs couches suit `seed → staging → snapshot → intermediate →
   marts → test`, jamais en parallèle ni dans un autre ordre — les
   snapshots lisent les modèles staging, l'intermediate lit les
   snapshots.
3. **Générer les nouveaux modèles staging avec `/new-stg`** plutôt qu'à
   la main, pour rester sur le pattern commun.
4. **Valider avant de commit :**
   ```bash
   dbt run --select <model>
   dbt test --select <model>
   ```
   Un modèle staging ajouté a au minimum des tests `not_null`/`unique`
   sur `id_stg_*` et le code métier, plus `accepted_values` si le domaine
   de valeurs est fermé (ex: `cd_pos_typ` ∈ {T, C}).
5. **Commit avec un scope explicite** — ne pas faire `git add -A` : sur
   ce projet le dossier `include/` (copie non versionnée du projet, dans
   `.gitignore`) et les artefacts `target/`/`*.duckdb` ne doivent jamais
   être stagés.

`.claude/settings.local.json` autorise sans prompt interactif les
commandes `dbt seed|run|show|test` et `git add|commit|push` — c'est le
détail d'outillage qui permet à l'agent d'exécuter ce workflow de
validation sans confirmation manuelle à chaque étape. Les opérations
destructives (`push --force`, `reset --hard`, etc.) restent hors des
règles par défaut de l'agent, qui demande confirmation avant de les
exécuter même si `git push *` est présent dans la liste.

## 4. Le hook de validation YAML

Défini dans `.claude/settings.json` (versionné, contrairement à
`settings.local.json`) : un hook `PostToolUse` sur `Write|Edit` qui
filtre lui-même sur les fichiers `.yml`/`.yaml` et appelle
`.claude/hooks/validate_yaml.py "$f"` après chaque écriture. Le script
bloque (exit 2, message renvoyé à l'agent) si l'un des trois checks
échoue :

1. un loader YAML qui lève une erreur sur une **clé dupliquée** au lieu
   de la tolérer silencieusement ;
2. un check structurel : une entrée sous `columns:` ne doit contenir que
   des clés de colonne (`name`, `description`, `tests`, ...), jamais des
   clés réservées au niveau modèle (`columns`, `config`, ...) ;
3. `dbt parse`, en dernier filtre.

**Pourquoi ce hook existe :** deux bugs réels se sont produits pendant le
développement de ce projet et ont été trouvés tardivement, après coup —
un bloc `tests:` dupliqué dans `int_fct_mvt` (qui a fait disparaître
silencieusement un test `unique`), et une indentation cassée dans un
`schema.yml` qui a fait glisser l'entrée d'un modèle dans la liste
`columns:` du modèle précédent (qui a fait disparaître silencieusement
les 38 tests de ce modèle). Dans les deux cas, rien n'a levé d'erreur au
moment de l'édition.

**Pourquoi les approches naïves ne suffisent pas — vérifié empiriquement
avant d'écrire le hook, pas supposé :**

- `yaml.safe_load` seul ne détecte ni l'un ni l'autre cas : le spec YAML
  autorise les clés dupliquées dans un mapping (la dernière écrase
  silencieusement les précédentes), et une entrée mal indentée qui reste
  syntaxiquement valide n'est pas une erreur de parsing.
- `dbt parse` — même avec `--warn-error` — ne détecte non plus **aucun**
  des deux cas : exit 0 silencieux à chaque fois. `dbt list` derrière
  confirme que le test `unique` ou les 38 tests du modèle ont bien
  disparu du manifest, sans qu'aucune commande dbt ne l'ait signalé.

**Limite connue, gardée volontairement dans le hook malgré tout :**
`dbt parse` reste utile comme 3e filtre pour de vraies casses de syntaxe
(indentation qui casse complètement le YAML, Jinja invalide), mais il
s'est avéré plus permissif que prévu sur d'autres cas testés pendant la
construction de ce hook : une `ref()` cassée dans les arguments d'un
test (`to: ref('modele_qui_n_existe_pas')`), un nom de test macro
inexistant, et une valeur `materialized` invalide passent tous les
trois avec exit 0, sans même apparaître dans `dbt list`. Ces trois cas
ne sont pas couverts par ce hook.
