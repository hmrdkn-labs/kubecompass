#!/usr/bin/env python3
"""Validate KubeCompass' Interface IR using only the Python standard library.

The schema is deliberately resolved relative to this repository, so the
validator remains useful after publishing or cloning KubeCompass elsewhere.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


PLATFORMS = {"web", "webapp", "tui"}
SUPPORT = {"native", "adapted", "unsupported"}
REQUIRED = (
    "schema_version", "kind", "name", "platform", "provenance", "tokens",
    "capabilities", "regions", "components", "states", "events", "actions",
    "focus", "navigation", "media", "motion", "evaluation",
)
SCHEMA_PATH = Path(__file__).resolve().parents[1] / "docs" / "interface" / "interface-system.schema.json"


def _json_type(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return True


def _equal(left: Any, right: Any) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left == right
    return left == right


def _ref(root: dict[str, Any], reference: str) -> Any:
    if not reference.startswith("#/"):
        raise ValueError(f"unsupported schema reference {reference!r}")
    value: Any = root
    for token in reference[2:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        value = value[int(token)] if isinstance(value, list) else value[token]
    return value


def _schema(value: Any, schema: dict[str, Any], path: str, root: dict[str, Any], errors: list[str]) -> None:
    if "$ref" in schema:
        try:
            _schema(value, _ref(root, schema["$ref"]), path, root, errors)
        except (KeyError, TypeError, ValueError) as exc:
            errors.append(f"{path} has an invalid schema reference: {exc}")
        return
    for child in schema.get("allOf", []):
        _schema(value, child, path, root, errors)
    if "const" in schema and not _equal(value, schema["const"]):
        errors.append(f"{path} must equal {schema['const']!r}")
    if "enum" in schema and not any(_equal(value, item) for item in schema["enum"]):
        errors.append(f"{path} must be one of {schema['enum']!r}")
    expected = schema.get("type")
    if expected is not None:
        types = expected if isinstance(expected, list) else [expected]
        if not any(_json_type(value, item) for item in types):
            errors.append(f"{path} must be of type {expected!r}")
            return
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}.{key} is required by schema")
        properties = schema.get("properties", {})
        for key, child in properties.items():
            if key in value:
                _schema(value[key], child, f"{path}.{key}", root, errors)
        additional = schema.get("additionalProperties", True)
        for key, child in value.items():
            if key in properties:
                continue
            if additional is False:
                errors.append(f"{path}.{key} is not allowed by schema")
            elif isinstance(additional, dict):
                _schema(child, additional, f"{path}.{key}", root, errors)
    if isinstance(value, list):
        minimum = schema.get("minItems")
        if minimum is not None and len(value) < minimum:
            errors.append(f"{path} must contain at least {minimum} item(s)")
        items = schema.get("items")
        if isinstance(items, dict):
            for index, child in enumerate(value):
                _schema(child, items, f"{path}[{index}]", root, errors)
    if isinstance(value, str) and "minLength" in schema and len(value) < schema["minLength"]:
        errors.append(f"{path} must contain at least {schema['minLength']} character(s)")


def _object(value: Any, path: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{path} must be an object")
        return {}
    return value


def _list(value: Any, path: str, errors: list[str]) -> list[Any]:
    if not isinstance(value, list):
        errors.append(f"{path} must be an array")
        return []
    return value


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _provenance(value: Any, path: str, errors: list[str]) -> None:
    item = _object(value, path, errors)
    if item.get("status") not in {"observed", "inferred", "unknown"}:
        errors.append(f"{path}.status must be observed, inferred, or unknown")
    if not _text(item.get("source")):
        errors.append(f"{path}.source must be a non-empty string")
    if not isinstance(item.get("note"), str):
        errors.append(f"{path}.note must be a string")


def _ids(items: list[Any], path: str, errors: list[str]) -> set[str]:
    found: set[str] = set()
    for index, item in enumerate(items):
        item_path = f"{path}[{index}]"
        if not isinstance(item, dict) or not _text(item.get("id")):
            errors.append(f"{item_path}.id must be a non-empty string")
            continue
        if item["id"] in found:
            errors.append(f"{item_path}.id duplicates {item['id']!r}")
        found.add(item["id"])
    return found


def validate_document(document: Any) -> list[str]:
    """Return contract violations; an empty list means the IR is valid."""
    errors: list[str] = []
    try:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"could not read interface schema: {exc}"]
    _schema(document, schema, "$", schema, errors)
    root = _object(document, "$", errors)
    for key in REQUIRED:
        if key not in root:
            errors.append(f"$.{key} is required")
    if root.get("schema_version") != "1.0":
        errors.append("$.schema_version must be '1.0'")
    if root.get("kind") != "interface-ir":
        errors.append("$.kind must be 'interface-ir'")
    if not _text(root.get("name")):
        errors.append("$.name must be a non-empty string")
    if root.get("platform") not in PLATFORMS:
        errors.append("$.platform must be one of web, webapp, tui")

    _provenance(root.get("provenance"), "$.provenance", errors)
    tokens = _object(root.get("tokens"), "$.tokens", errors)
    _provenance(tokens.get("provenance"), "$.tokens.provenance", errors)
    for key in ("color", "type", "space", "radius", "motion"):
        token_map = _object(tokens.get(key), f"$.tokens.{key}", errors)
        for token_name, token in token_map.items():
            path = f"$.tokens.{key}.{token_name}"
            token = _object(token, path, errors)
            for required in ("type", "value", "unit", "provenance"):
                if required not in token:
                    errors.append(f"{path}.{required} is required")
            if not _text(token.get("type")):
                errors.append(f"{path}.type must be a non-empty string")
            if token.get("unit") is not None and not isinstance(token.get("unit"), str):
                errors.append(f"{path}.unit must be a string or null")
            _provenance(token.get("provenance"), f"{path}.provenance", errors)

    capabilities = _object(root.get("capabilities"), "$.capabilities", errors)
    for capability_id, capability in capabilities.items():
        path = f"$.capabilities.{capability_id}"
        capability = _object(capability, path, errors)
        support = _object(capability.get("support"), f"{path}.support", errors)
        for runtime in PLATFORMS:
            if support.get(runtime) not in SUPPORT:
                errors.append(f"{path}.support.{runtime} must be native, adapted, or unsupported")
        if not _text(capability.get("fallback")):
            errors.append(f"{path}.fallback must be a non-empty string")
        if capability.get("requirement") not in {"required", "optional", "unavailable"}:
            errors.append(f"{path}.requirement must be required, optional, or unavailable")
        _provenance(capability.get("provenance"), f"{path}.provenance", errors)
        mapping = _object(capability.get("mapping_provenance"), f"{path}.mapping_provenance", errors)
        for runtime in PLATFORMS:
            _provenance(mapping.get(runtime), f"{path}.mapping_provenance.{runtime}", errors)

    regions = _list(root.get("regions"), "$.regions", errors)
    components = _list(root.get("components"), "$.components", errors)
    states = _list(root.get("states"), "$.states", errors)
    events = _list(root.get("events"), "$.events", errors)
    actions = _list(root.get("actions"), "$.actions", errors)
    media = _list(root.get("media"), "$.media", errors)
    region_ids = _ids(regions, "$.regions", errors)
    component_ids = _ids(components, "$.components", errors)
    state_ids = _ids(states, "$.states", errors)
    event_ids = _ids(events, "$.events", errors)
    action_ids = _ids(actions, "$.actions", errors)
    media_ids = _ids(media, "$.media", errors)

    for index, region in enumerate(regions):
        if not isinstance(region, dict):
            continue
        path = f"$.regions[{index}]"
        _provenance(region.get("provenance"), f"{path}.provenance", errors)
        for child in _list(region.get("children"), f"{path}.children", errors):
            if child not in component_ids and child not in region_ids:
                errors.append(f"{path}.children references unknown id {child!r}")
    for index, component in enumerate(components):
        if not isinstance(component, dict):
            continue
        path = f"$.components[{index}]"
        _provenance(component.get("provenance"), f"{path}.provenance", errors)
        if not _text(component.get("kind")):
            errors.append(f"{path}.kind must be a non-empty string")
        if component.get("region") not in region_ids:
            errors.append(f"{path}.region references an unknown region")
        for field, known in (("capabilities", set(capabilities)), ("states", state_ids), ("events", event_ids), ("actions", action_ids)):
            for value in _list(component.get(field), f"{path}.{field}", errors):
                if value not in known:
                    errors.append(f"{path}.{field} references unknown id {value!r}")
    for index, state in enumerate(states):
        if not isinstance(state, dict):
            continue
        path = f"$.states[{index}]"
        _provenance(state.get("provenance"), f"{path}.provenance", errors)
        values = _list(state.get("values"), f"{path}.values", errors)
        if not values:
            errors.append(f"{path}.values must not be empty")
        if state.get("initial") not in values:
            errors.append(f"{path}.initial must be one of values")

    for collection, path, known in ((events, "$.events", component_ids | action_ids), (actions, "$.actions", component_ids)):
        for index, item in enumerate(collection):
            if not isinstance(item, dict):
                continue
            item_path = f"{path}[{index}]"
            _provenance(item.get("provenance"), f"{item_path}.provenance", errors)
            for target in _list(item.get("targets"), f"{item_path}.targets", errors):
                if target not in known:
                    errors.append(f"{item_path}.targets references unknown id {target!r}")
    focus = _object(root.get("focus"), "$.focus", errors)
    for target in _list(focus.get("order"), "$.focus.order", errors):
        if target not in component_ids:
            errors.append(f"$.focus.order references unknown component {target!r}")
    if not isinstance(focus.get("trap"), bool):
        errors.append("$.focus.trap must be boolean")
    if focus.get("default") is not None and focus.get("default") not in component_ids:
        errors.append("$.focus.default references an unknown component")
    navigation = _object(root.get("navigation"), "$.navigation", errors)
    if navigation.get("mode") not in {"spatial", "linear", "mixed", "none"}:
        errors.append("$.navigation.mode is invalid")
    for index, link in enumerate(_list(navigation.get("links"), "$.navigation.links", errors)):
        if not isinstance(link, dict):
            continue
        for endpoint in ("from", "to"):
            if link.get(endpoint) not in component_ids:
                errors.append(f"$.navigation.links[{index}].{endpoint} references an unknown component")
    for index, item in enumerate(media):
        if not isinstance(item, dict):
            continue
        path = f"$.media[{index}]"
        _provenance(item.get("provenance"), f"{path}.provenance", errors)
        if item.get("type") not in {"image", "video", "audio", "icon", "none"}:
            errors.append(f"{path}.type is invalid")
        if not _text(item.get("fallback")):
            errors.append(f"{path}.fallback must be a non-empty string")
        if not isinstance(item.get("implementation_safe"), bool):
            errors.append(f"{path}.implementation_safe must be boolean")
    motion = _object(root.get("motion"), "$.motion", errors)
    if not isinstance(motion.get("allowed"), bool):
        errors.append("$.motion.allowed must be boolean")
    if motion.get("reduced_motion") not in {"preserve", "reduce", "remove"}:
        errors.append("$.motion.reduced_motion is invalid")
    for index, transition in enumerate(_list(motion.get("transitions"), "$.motion.transitions", errors)):
        path = f"$.motion.transitions[{index}]"
        transition = _object(transition, path, errors)
        for required in ("id", "from", "to"):
            if not _text(transition.get(required)):
                errors.append(f"{path}.{required} must be a non-empty string")
        _provenance(transition.get("provenance"), f"{path}.provenance", errors)
    evaluation = _object(root.get("evaluation"), "$.evaluation", errors)
    for index, criterion in enumerate(_list(evaluation.get("criteria"), "$.evaluation.criteria", errors)):
        path = f"$.evaluation.criteria[{index}]"
        criterion = _object(criterion, path, errors)
        for key in ("id", "statement"):
            if not _text(criterion.get(key)):
                errors.append(f"{path}.{key} must be a non-empty string")
        _provenance(criterion.get("provenance"), f"{path}.provenance", errors)
    if evaluation.get("status") not in {"draft", "tested", "accepted", "rejected"}:
        errors.append("$.evaluation.status is invalid")
    for index, evidence in enumerate(_list(evaluation.get("evidence"), "$.evaluation.evidence", errors)):
        path = f"$.evaluation.evidence[{index}]"
        evidence = _object(evidence, path, errors)
        for key in ("id", "source", "summary"):
            if not _text(evidence.get(key)):
                errors.append(f"{path}.{key} must be a non-empty string")
        _provenance(evidence.get("provenance"), f"{path}.provenance", errors)
    if len(media_ids) != len(media):
        errors.append("$.media contains duplicate or missing ids")
    return errors


def load_and_validate(path: Path) -> list[str]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return [f"file not found: {path}"]
    except (OSError, json.JSONDecodeError) as exc:
        return [f"could not read JSON: {exc}"]
    return validate_document(document)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("interface", type=Path, help="Interface IR JSON file")
    args = parser.parse_args(argv)
    errors = load_and_validate(args.interface)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"VALID: {args.interface}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
