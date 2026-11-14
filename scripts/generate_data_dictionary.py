"""Generate docs/data_dictionary.md from dbt artifacts.

Run after `dbt docs generate --target prod`, which writes target/manifest.json
(descriptions) and target/catalog.json (actual Snowflake column types).

    python scripts/generate_data_dictionary.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LAYERS = [
    ("Gold – Reporting Marts", "models/gold/reporting/"),
    ("Gold – Facts", "models/gold/facts/"),
    ("Gold – Dimensions", "models/gold/dimensions/"),
    ("Silver – Intermediate", "models/silver/intermediate/"),
    ("Silver – Staging", "models/silver/staging/"),
    ("Seeds", "seeds/"),
]


def clean(text: str) -> str:
    return " ".join((text or "").split()).replace("|", "\\|")


def main() -> None:
    manifest = json.loads((ROOT / "target/manifest.json").read_text())
    catalog = json.loads((ROOT / "target/catalog.json").read_text())
    nodes = [
        n for n in manifest["nodes"].values()
        if n["resource_type"] in ("model", "seed") and n["package_name"] == "kaggle_dwh"
    ]

    out = [
        "# Data Dictionary",
        "",
        "Generated from dbt metadata by `scripts/generate_data_dictionary.py`. "
        "Do not edit by hand; update the model YAML files and regenerate. "
        "Types are the actual Snowflake column types.",
        "",
    ]
    for title, prefix in LAYERS:
        layer = sorted(
            (n for n in nodes if n["original_file_path"].startswith(prefix)),
            key=lambda n: n["name"],
        )
        if not layer:
            continue
        out += [f"## {title}", ""]
        for node in layer:
            cat = catalog["nodes"].get(node["unique_id"], {})
            schema = cat.get("metadata", {}).get("schema", node["schema"])
            out += [
                f"### `{node['name']}`",
                "",
                f"**Location:** `{node['database']}.{schema}.{node['name'].upper()}`",
                "",
                clean(node.get("description")),
                "",
                "| Column | Type | Description |",
                "|---|---|---|",
            ]
            documented = {k.lower(): v for k, v in node["columns"].items()}
            actual = sorted(cat.get("columns", {}).values(), key=lambda c: c["index"])
            for col in actual:
                name = col["name"].lower()
                desc = clean(documented.get(name, {}).get("description", ""))
                out.append(f"| `{name}` | {col['type']} | {desc} |")
            out.append("")

    path = ROOT / "docs/data_dictionary.md"
    path.write_text("\n".join(out))
    print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
