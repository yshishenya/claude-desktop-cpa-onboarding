#!/usr/bin/env python3
"""Create Claude-friendly aliases for the main CPA models and grant them to keys.

Claude Desktop only accepts model names that look like Anthropic models.  This
script creates one alias per main model on the CPA policy plugin and grants
those aliases to CPA keys.  It is an admin tool: it needs the CPA management
key.

The macOS installer only writes the alias names into Claude Desktop.  It does
not need the management key.
"""

from __future__ import annotations

import argparse
import datetime as dt
import getpass
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_URL = "https://cpa.2brain.pro"
API_PREFIX = "/v0/management/plugins/cpa-key-policy"

# The GPT aliases below are what Claude Desktop shows for the main CPA models.
# Alias names say which model they point to (astra, sol, terra, luna + version)
# and that they are for Claude Code; they cannot contain gpt/codex/deepseek,
# because Claude Desktop drops such names. Keep in sync with MAIN_MODEL_SPECS in
# install.sh and MainModels in install.ps1 (a test checks this).
MAIN_MODELS = [
    {
        "alias": "opus-astra-6-2-claude-code",
        "source": "gpt-6.2-astra",
        "label": "GPT 6.2 Astra",
        "tier": "opus",
        "behaves_as": "claude-opus-5-5",
    },
    {
        "alias": "sonnet-sol-6-2-claude-code",
        "source": "gpt-6.2-sol",
        "label": "GPT 6.2 Sol",
        "tier": "sonnet",
        "behaves_as": "claude-sonnet-5",
    },
    {
        "alias": "sonnet-terra-6-1-claude-code",
        "source": "gpt-6.1-terra",
        "label": "GPT 6.1 Terra",
        "tier": "sonnet",
        "behaves_as": "claude-sonnet-5",
    },
    {
        "alias": "haiku-luna-6-claude-code",
        "source": "gpt-6-luna",
        "label": "GPT-6 Luna",
        "tier": "haiku",
        "behaves_as": "claude-haiku-5-5",
    },
]

# The three base Claude 5.5 models. Their global aliases already exist (alias ==
# source), so the script only grants them to keys: no new alias is created.
CLAUDE_MODELS = [
    {"alias": name, "source": name, "label": label, "tier": tier, "behaves_as": name}
    for name, label, tier in (
        ("claude-opus-5-5", "Claude Opus 5.5", "opus"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5", "sonnet"),
        ("claude-haiku-5-5", "Claude Haiku 5.5", "haiku"),
    )
]

# What the script creates and grants.
MODELS = MAIN_MODELS + CLAUDE_MODELS


class ApiError(RuntimeError):
    pass


def api(method: str, url: str, token: str, payload: dict | None = None) -> dict:
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:300]
        raise ApiError(f"{method} {url}: HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise ApiError(f"{method} {url}: {exc.reason}") from exc
    return json.loads(body) if body else {}


def management_token(path: str | None) -> str:
    if path:
        with open(path, encoding="utf-8") as handle:
            token = handle.read().strip()
        if token:
            return token
        sys.exit(f"Пустой management key: {path}")
    token = os.environ.get("CPA_MANAGEMENT_KEY", "").strip()
    if token:
        return token
    if sys.stdin.isatty():
        token = getpass.getpass("CPA management key: ").strip()
        if token:
            return token
    sys.exit(
        "Нужен management key CPA. Передайте CPA_MANAGEMENT_KEY, "
        "--management-key-file или введите его в терминале."
    )


def alias_list(payload: dict) -> list[dict]:
    aliases = payload.get("aliases", payload if isinstance(payload, list) else [])
    return [item for item in aliases if isinstance(item, dict) and item.get("alias")]


def key_list(payload: dict) -> list[dict]:
    keys = payload.get("keys", [])
    return [item for item in keys if isinstance(item, dict) and item.get("id")]


def key_model_entries(key: dict, alias: str) -> list[dict]:
    return [
        item
        for item in (key.get("models") or [])
        if isinstance(item, dict) and item.get("alias") == alias
    ]


def key_alias_names(key: dict) -> set[str]:
    """Alias names in the key's `aliases` field (entries are {"alias": name} or plain names)."""
    return {
        item.get("alias") if isinstance(item, dict) else item
        for item in (key.get("aliases") or [])
    }


def save_snapshot(backup_dir: str, aliases: list, keys: list) -> str:
    """Save the policy before a change. A name is never reused, so a snapshot is never overwritten."""
    backup_dir = os.path.abspath(backup_dir)
    os.makedirs(backup_dir, mode=0o700, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    path = os.path.join(backup_dir, f"cpa-policy-backup-{stamp}.json")
    counter = 1
    while os.path.exists(path):
        counter += 1
        path = os.path.join(backup_dir, f"cpa-policy-backup-{stamp}-{counter}.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump({"aliases": aliases, "keys": keys}, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.chmod(path, 0o600)
    return path


def revoke(args, token: str, api_base: str) -> int:
    """Take old aliases away from the named keys. Global aliases are not touched."""
    managed = {item["alias"] for item in MODELS}
    asked = list(dict.fromkeys(args.revoke_alias))
    protected = [name for name in asked if name in managed]
    if protected:
        sys.exit("Эти alias входят в управляемый набор, отзывать их нельзя: " + ", ".join(protected))
    if not args.key_name or args.all_keys:
        sys.exit("Для --revoke-alias укажите ключи через --key-name (--all-keys не допускается).")

    aliases = alias_list(api("GET", api_base + "/aliases", token))
    keys = key_list(api("GET", api_base + "/keys", token))
    wanted = set(args.key_name)
    targets = [key for key in keys if key.get("name") in wanted]
    for name in sorted(wanted - {key.get("name") for key in targets}):
        print(f"  ! ключ не найден: {name}")

    print("== План (отзыв) ==")
    updates = []
    for key in targets:
        in_models = {m["alias"] for m in (key.get("models") or []) if isinstance(m, dict)}
        present = [name for name in asked if name in in_models or name in key_alias_names(key)]
        if not present:
            print(f"  = ключ {key.get('name')}: этих alias нет")
            continue
        for name in present:
            routes = len(key_model_entries(key, name))
            print(f"  - ключ {key.get('name')}: убрать {name} ({routes} маршрут(ов))")
        updates.append((key, present))
    global_names = {item["alias"] for item in aliases}
    for name in asked:
        if name not in global_names:
            print(f"  ! {name}: такого глобального alias нет")

    if not args.apply:
        print("\nПроверка завершена. Для применения добавьте --apply.")
        return 0
    if not updates:
        print("\nМеняться нечему.")
        return 0

    backup_path = save_snapshot(args.backup_dir, aliases, keys)
    print(f"\nСнимок политики: {backup_path}")

    for key, present in updates:
        drop = set(present)
        models = [m for m in (key.get("models") or []) if not (isinstance(m, dict) and m.get("alias") in drop)]
        aliases_field = [
            item for item in (key.get("aliases") or [])
            if (item.get("alias") if isinstance(item, dict) else item) not in drop
        ]
        # Both fields are sent: a PATCH that changes only one can be rolled back.
        payload = {
            "id": key["id"],
            "name": key.get("name", ""),
            "enabled": key.get("enabled", True),
            "rpm": key.get("rpm", 0),
            "daily_limit_usd": key.get("daily_limit_usd", 0),
            "weekly_limit_usd": key.get("weekly_limit_usd", 0),
            "allow_models_endpoint": key.get("allow_models_endpoint", True),
            "models": models,
            "aliases": aliases_field,
        }
        api("PATCH", api_base + "/keys", token, payload)
        print(f"  обновлён ключ {key.get('name') or key['id']}")

    keys_after = {key["id"]: key for key in key_list(api("GET", api_base + "/keys", token))}
    aliases_after = alias_list(api("GET", api_base + "/aliases", token))
    problems = []
    if aliases_after != aliases:
        problems.append("глобальные alias изменились")
    touched = {key["id"] for key, _ in updates}
    for key in keys:
        after = keys_after.get(key["id"], {})
        if key["id"] not in touched:
            if {f: v for f, v in after.items() if f not in ("updated_at", "usage")} != {
                f: v for f, v in key.items() if f not in ("updated_at", "usage")
            }:
                problems.append(f"изменился ключ, который не выбирали: {key.get('name')}")
    for key, present in updates:
        after = keys_after.get(key["id"], {})
        label = key.get("name") or key["id"]
        left_models = {m["alias"] for m in (after.get("models") or [])}
        left_aliases = key_alias_names(after)
        for name in present:
            if name in left_models or name in left_aliases:
                problems.append(f"{label}: {name} всё ещё есть")
        expected = {m["alias"] for m in (key.get("models") or [])} - set(present)
        if left_models != expected or left_aliases != (key_alias_names(key) - set(present)):
            problems.append(f"{label}: изменилось что-то кроме отозванных alias")
    if problems:
        print("\nПроверка не прошла:")
        for problem in problems:
            print("  ! " + problem)
        return 1
    print("\nГотово. Проверка прошла.")
    return 0


def build_route(source: dict) -> dict:
    route = {
        "alias": source["alias"],
        "targets": source.get("targets") or [],
        "dispatch": source.get("dispatch", "round-robin"),
        "billing_mode": source.get("billing_mode", "tokens"),
    }
    if not route["targets"]:
        raise SystemExit(f"У alias {source['alias']} нет targets")
    return route


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Создать Claude-алиасы для основных моделей CPA и выдать их ключам. "
            "По умолчанию показывает план и ничего не меняет."
        )
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("CPA_MANAGEMENT_URL", DEFAULT_URL),
        help=f"Адрес CPA (по умолчанию {DEFAULT_URL})",
    )
    parser.add_argument(
        "--management-key-file",
        help="Файл с management key (по умолчанию CPA_MANAGEMENT_KEY)",
    )
    parser.add_argument(
        "--key-name",
        action="append",
        default=[],
        help="Имя ключа CPA, которому выдать alias. Можно повторять.",
    )
    parser.add_argument(
        "--all-keys",
        action="store_true",
        help="Выдать alias всем существующим ключам CPA.",
    )
    parser.add_argument(
        "--revoke-alias",
        action="append",
        default=[],
        help=(
            "Забрать этот alias у ключей из --key-name (режим отзыва: ничего не "
            "выдаётся, глобальные alias не удаляются). Можно повторять."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Применить изменения. Без флага выполняется только проверка.",
    )
    parser.add_argument(
        "--backup-dir",
        default=".",
        help="Куда сохранить снимок политики перед изменениями (по умолчанию текущая папка).",
    )
    args = parser.parse_args()

    if args.apply and not args.key_name and not args.all_keys:
        parser.error("для --apply укажите --key-name или --all-keys")

    base = args.url.rstrip("/")
    token = management_token(args.management_key_file)
    api_base = base + API_PREFIX

    if args.revoke_alias:
        return revoke(args, token, api_base)

    aliases = alias_list(api("GET", api_base + "/aliases", token))
    keys = key_list(api("GET", api_base + "/keys", token))
    aliases_by_name = {item["alias"]: item for item in aliases}

    print("== План ==")
    missing_routes = []
    for model in MODELS:
        source = aliases_by_name.get(model["source"])
        if source is None:
            print(f"  ! {model['source']}: нет глобального alias, пропускаю")
            continue
        existing = aliases_by_name.get(model["alias"])
        if existing is None:
            print(f"  + alias {model['alias']} -> {model['source']}")
            missing_routes.append((model, source))
        else:
            print(f"  = alias {model['alias']} уже есть")

    targets = keys
    if args.key_name:
        wanted = set(args.key_name)
        targets = [key for key in keys if key.get("name") in wanted]
        found = {key.get("name") for key in targets}
        for name in sorted(wanted - found):
            print(f"  ! ключ не найден: {name}")
    elif not args.all_keys:
        print("  (ключи не выбраны: укажите --key-name или --all-keys)")

    key_updates = []
    for key in targets:
        additions = []
        for model in MODELS:
            alias = model["alias"]
            source = aliases_by_name.get(model["source"])
            if source is None:
                continue
            if key_model_entries(key, alias):
                continue
            for target in source.get("targets") or []:
                entry = {
                    "alias": alias,
                    "provider": target.get("provider", ""),
                    "target_model": target.get("target_model", ""),
                    "billing_mode": source.get("billing_mode", "tokens"),
                }
                if target.get("group"):
                    entry["group"] = target["group"]
                additions.append(entry)
        if additions:
            print(
                "  + ключ %s: %d маршрут(ов) для %d моделей"
                % (key.get("name") or key["id"], len(additions), len(MODELS))
            )
            key_updates.append((key, additions))

    if not args.apply:
        print("\nПроверка завершена. Для применения добавьте --apply.")
        return 0

    backup_path = save_snapshot(args.backup_dir, aliases, keys)
    print(f"\nСнимок политики: {backup_path}")

    for model, source in missing_routes:
        route = build_route({**source, "alias": model["alias"]})
        api("POST", api_base + "/aliases", token, route)
        print(f"  создан alias {model['alias']}")

    for key, additions in key_updates:
        models = list(key.get("models") or [])
        models.extend(additions)
        # Key Policy keeps the allowed aliases in two fields, `models` and
        # `aliases`. A PATCH that changes only one of them reports success but can
        # be rolled back from the other, so both are sent and kept consistent.
        aliases_field = list(key.get("aliases") or [])
        present = key_alias_names(key)
        for item in additions:
            if item["alias"] not in present:
                present.add(item["alias"])
                aliases_field.append({"alias": item["alias"]})
        payload = {
            "id": key["id"],
            "name": key.get("name", ""),
            "enabled": key.get("enabled", True),
            "rpm": key.get("rpm", 0),
            "daily_limit_usd": key.get("daily_limit_usd", 0),
            "weekly_limit_usd": key.get("weekly_limit_usd", 0),
            "allow_models_endpoint": key.get("allow_models_endpoint", True),
            "models": models,
            "aliases": aliases_field,
        }
        api("PATCH", api_base + "/keys", token, payload)
        print(f"  обновлён ключ {key.get('name') or key['id']}")

    # Read back and verify the intended changes.
    aliases_after = {item["alias"] for item in alias_list(api("GET", api_base + "/aliases", token))}
    keys_after = {key["id"]: key for key in key_list(api("GET", api_base + "/keys", token))}
    problems = []
    for model in MODELS:
        if model["source"] not in aliases_after:
            continue
        if model["alias"] not in aliases_after:
            problems.append(f"alias не создан: {model['alias']}")
    for key, _ in key_updates:
        after = keys_after.get(key["id"], {})
        for model in MODELS:
            if model["source"] not in aliases_after:
                continue
            if not key_model_entries(after, model["alias"]):
                problems.append(
                    f"{key.get('name') or key['id']}: нет {model['alias']} в models"
                )
            if model["alias"] not in key_alias_names(after):
                problems.append(
                    f"{key.get('name') or key['id']}: нет {model['alias']} в aliases"
                )
    if problems:
        print("\nПроверка не прошла:")
        for problem in problems:
            print("  ! " + problem)
        return 1

    print("\nГотово. Проверка прошла.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ApiError as exc:
        sys.exit(f"ERROR: {exc}")
