#!/usr/bin/env python3
"""Validate a dbt YAML file after Claude Code writes/edits it.

Used by the PostToolUse hook in .claude/settings.json. Three checks, in
order, each catching a failure mode the others miss:

1. YAML syntax + duplicate keys (plain yaml.safe_load tolerates duplicate
   mapping keys per the YAML spec -- it silently keeps the last one, which
   is exactly how a duplicated `tests:` block under one column went
   unnoticed in this project before: the first test list just vanished).
2. Column/model key structure -- catches a model's schema.yml block
   silently swallowed into the wrong parent's `columns:` list by a bad
   indent. This stays syntactically valid YAML and `dbt parse` does not
   flag it (verified empirically), so it needs its own check.
3. `dbt parse`, as a last filter for everything else (broken ref(),
   invalid Jinja, unknown config keys).

Exit 0 = OK. Exit 2 = blocking error, printed to stderr for the agent to see.
"""
import subprocess
import sys

import yaml

MODEL_ONLY_KEYS = {
    "columns", "config", "constraints", "access",
    "latest_version", "versions", "deprecation_date",
    "freshness", "loaded_at_field",
}


class UniqueKeyLoader(yaml.SafeLoader):
    """Raises on duplicate mapping keys instead of silently keeping the last one."""

    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise ValueError(f"duplicate key {key!r}")
            seen.add(key)
        return super().construct_mapping(node, deep)


def check_column_structure(path, data):
    problems = []
    for model in data.get("models") or []:
        if not isinstance(model, dict):
            continue
        for col in model.get("columns") or []:
            if not isinstance(col, dict):
                continue
            bad = set(col.keys()) & MODEL_ONLY_KEYS
            if bad:
                problems.append(
                    f"column {col.get('name')!r} of model {model.get('name')!r} "
                    f"has model-level keys {sorted(bad)} -- likely a model block "
                    "swallowed by the wrong parent (check indentation)."
                )
    return problems


def main():
    if len(sys.argv) != 2:
        print("usage: validate_yaml.py <file.yml>", file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]

    try:
        with open(path) as f:
            data = yaml.load(f, Loader=UniqueKeyLoader)
    except Exception as e:
        print(f"YAML validation failed for {path}: {e}", file=sys.stderr)
        sys.exit(2)

    if isinstance(data, dict) and "models" in data:
        problems = check_column_structure(path, data)
        if problems:
            print(f"YAML structural check failed for {path}:", file=sys.stderr)
            for p in problems:
                print(f"  - {p}", file=sys.stderr)
            sys.exit(2)

    result = subprocess.run(
        ["dbt", "parse", "--quiet"], capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"dbt parse failed after editing {path}:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
