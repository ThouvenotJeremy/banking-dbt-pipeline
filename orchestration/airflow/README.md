# Orchestration Airflow

Orchestration du pipeline dbt banking via Apache Airflow (Astronomer Runtime).

## Vue d'ensemble

Le DAG `banking_dbt_pipeline` exécute le pipeline dbt complet dans l'ordre
imposé par l'architecture en couches :
seed → run staging → snapshot → run intermediate → run marts → test

L'ordre est strict : le staging précède les snapshots (qui lisent `stg_cli`
et `stg_ptf`), et les snapshots précèdent l'intermediate (historisation SCD2).

Planification : jours ouvrés à 23h (`0 23 * * 1-5`), après clôture des marchés.

## Stack

- **Astronomer Runtime** (Airflow 3.x)
- **dbt-duckdb** pour l'environnement de démonstration
- **BashOperator** pour l'exécution des commandes dbt

## Prérequis

- [Astro CLI](https://www.astronomer.io/docs/astro/cli/install-cli)
- Docker Desktop

## Lancement en local

Le DAG lit le projet dbt monté dans `include/`. Depuis un projet Astro :

1. Copier le projet dbt dans `include/` :
```bash
   cp -r /chemin/vers/banking-dbt-pipeline include/
   rm -rf include/banking-dbt-pipeline/.venv \
          include/banking-dbt-pipeline/dev.duckdb \
          include/banking-dbt-pipeline/target \
          include/banking-dbt-pipeline/logs
```

2. Démarrer Airflow :
```bash
   astro dev start
```

3. Ouvrir l'UI Airflow (l'URL est affichée au démarrage, ex.
   `http://localhost:8080`), activer le DAG `banking_dbt_pipeline`
   et le déclencher manuellement.

## Structure

orchestration/airflow/
├── dags/
│   └── banking_pipeline_dag.py   # DAG principal
├── Dockerfile                    # Image Astro Runtime
├── requirements.txt              # dbt-core, dbt-duckdb, cosmos...
└── README.md


## Passage en production (Snowflake)

Pour une exécution réelle sur Snowflake plutôt que DuckDB :

1. Adapter `requirements.txt` (déjà inclut `dbt-snowflake`).
2. Injecter les credentials Snowflake via variables d'environnement Astro
   ou une connexion Airflow, consommées par `profiles.yml` avec `env_var()`.
3. Passer le `--target` des commandes dbt de `dev` (DuckDB) à `prod` (Snowflake).