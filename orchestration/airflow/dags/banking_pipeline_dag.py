"""
DAG d'orchestration du pipeline DBT banking.

Architecture en 4 couches :
    ST0 (seeds) -> Staging -> Snapshot -> Intermediate -> Marts

Chaque couche ne dépend que de la précédente. Le pipeline tourne sur DuckDB
(environnement de démonstration). L'ordre d'exécution est strict :
le staging doit précéder les snapshots (qui lisent stg_cli / stg_ptf),
et les snapshots doivent précéder l'intermediate (SCD2 historisé).

Planifié en semaine à 23h (après clôture des marchés).
"""

from datetime import datetime, timedelta
from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.empty import EmptyOperator

# Chemin du projet dbt monté dans le container via include/
DBT_PROJECT_DIR = "/usr/local/airflow/include/banking-dbt-pipeline"

# Profil DuckDB généré à la volée (pas de secrets, environnement de démo)
DBT_SETUP = (
    "mkdir -p ~/.dbt && "
    "printf 'banking_pipeline:\\n"
    "  target: dev\\n"
    "  outputs:\\n"
    "    dev:\\n"
    "      type: duckdb\\n"
    "      path: dev.duckdb\\n"
    "      threads: 4\\n' > ~/.dbt/profiles.yml"
)

default_args = {
    "owner": "jeremy.thouvenot",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}


def dbt_cmd(command: str) -> str:
    """Compose une commande dbt : setup du profil + exécution dans le projet."""
    return f"{DBT_SETUP} && cd {DBT_PROJECT_DIR} && dbt {command}"


with DAG(
    dag_id="banking_dbt_pipeline",
    default_args=default_args,
    description="Pipeline DBT banking — ST0 -> Staging -> Snapshot -> Intermediate -> Marts",
    schedule="0 23 * * 1-5",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["banking", "dbt", "duckdb"],
) as dag:

    start = EmptyOperator(task_id="start")

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=dbt_cmd("deps"),
    )

    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command=dbt_cmd("seed --full-refresh"),
    )

    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=dbt_cmd("run --select staging"),
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=dbt_cmd("snapshot"),
    )

    dbt_run_intermediate = BashOperator(
        task_id="dbt_run_intermediate",
        bash_command=dbt_cmd("run --select intermediate"),
    )

    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=dbt_cmd("run --select marts"),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=dbt_cmd("test"),
    )

    end = EmptyOperator(task_id="end")

    (
        start
        >> dbt_deps
        >> dbt_seed
        >> dbt_run_staging
        >> dbt_snapshot
        >> dbt_run_intermediate
        >> dbt_run_marts
        >> dbt_test
        >> end
    )