#!/usr/bin/env python3
"""Enforce the strict layer-dependency rule from CLAUDE.md against target/manifest.json.

    staging      -> sources / seeds only
    intermediate -> staging models + snapshots only
    marts        -> intermediate models only (no mart -> mart, no mart -> staging)

Nothing in dbt itself checks this: a mart that reads a staging model directly
compiles and passes every dbt test without anyone noticing. This script is
the machine-enforced version of the rule.

Run after `dbt compile` (or any command that (re)writes target/manifest.json).
Exit 0 = no violations. Exit 1 = at least one violation, printed to stdout.
"""
import json
import sys
from pathlib import Path

MANIFEST_PATH = Path("target/manifest.json")

# original_file_path prefix -> layer name
LAYER_PREFIXES = {
    "models/staging/": "staging",
    "models/intermediate/": "intermediate",
    "models/marts/": "marts",
}

# layer -> set of dependency kinds allowed for a model in that layer.
# "source" / "seed" / "snapshot" refer to the resource_type of the dependency.
# "staging" / "intermediate" / "marts" refer to the *layer* of a model dependency.
ALLOWED_DEPENDENCY_KINDS = {
    "staging": {"source", "seed"},
    "intermediate": {"staging", "snapshot"},
    "marts": {"intermediate"},
}

RULE_DESCRIPTIONS = {
    "staging": "staging ne doit référencer que des sources/seeds (st0)",
    "intermediate": "intermediate ne doit référencer que des modèles staging ou des snapshots",
    "marts": "marts ne doit référencer que des modèles intermediate (pas d'autre mart, pas de staging)",
}


def load_manifest():
    if not MANIFEST_PATH.exists():
        print(
            f"Erreur : {MANIFEST_PATH} introuvable. Lancer `dbt compile` "
            "(ou `dbt parse`/`dbt run`) avant ce script.",
            file=sys.stderr,
        )
        sys.exit(1)
    with MANIFEST_PATH.open() as f:
        return json.load(f)


def model_layer(node):
    """Return the layer ('staging'/'intermediate'/'marts') for a model node,
    or None if its path doesn't fall under a known layer."""
    path = node.get("original_file_path", "")
    for prefix, layer in LAYER_PREFIXES.items():
        if path.startswith(prefix):
            return layer
    return None


def dependency_kind(dep_unique_id, nodes, layers_by_id):
    """Classify a depends_on.nodes entry: 'source', 'seed', 'snapshot',
    or the layer of the model it points to."""
    resource_type = dep_unique_id.split(".", 1)[0]
    if resource_type in ("source", "seed", "snapshot"):
        return resource_type
    if resource_type == "model":
        return layers_by_id.get(dep_unique_id)
    return f"unknown:{resource_type}"


def main():
    manifest = load_manifest()
    nodes = manifest.get("nodes", {})

    model_nodes = {
        uid: n for uid, n in nodes.items() if n.get("resource_type") == "model"
    }

    layers_by_id = {}
    unclassified = []
    for uid, node in model_nodes.items():
        layer = model_layer(node)
        layers_by_id[uid] = layer
        if layer is None:
            unclassified.append(uid)

    if unclassified:
        print(
            "Avertissement : modèles hors des couches connues "
            f"(models/staging|intermediate|marts), ignorés : {sorted(unclassified)}",
            file=sys.stderr,
        )

    violations = []
    for uid, node in model_nodes.items():
        layer = layers_by_id[uid]
        if layer is None:
            continue

        allowed = ALLOWED_DEPENDENCY_KINDS[layer]
        for dep_uid in node.get("depends_on", {}).get("nodes", []):
            kind = dependency_kind(dep_uid, nodes, layers_by_id)
            if kind not in allowed:
                violations.append(
                    {
                        "model": node.get("name", uid),
                        "model_path": node.get("original_file_path"),
                        "layer": layer,
                        "dependency": dep_uid,
                        "dependency_kind": kind,
                        "rule": RULE_DESCRIPTIONS[layer],
                    }
                )

    if violations:
        print(f"{len(violations)} violation(s) de la règle de dépendance stricte :\n")
        for v in violations:
            print(f"  Modèle fautif   : {v['model']}  ({v['model_path']})")
            print(f"  Dépendance      : {v['dependency']}  (couche/type: {v['dependency_kind']})")
            print(f"  Règle violée    : {v['rule']}")
            print()
        sys.exit(1)

    print(f"OK — {len(model_nodes)} modèles vérifiés, aucune violation de couche.")
    sys.exit(0)


if __name__ == "__main__":
    main()
