#!/usr/bin/env python3
"""Update versions.yml with the newest supported Ruby patch releases."""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from copy import deepcopy
from datetime import date
from pathlib import Path


VERSIONS_FILE = Path("versions.yml")
RUBY_BUILD_API = "https://api.github.com/repos/rbenv/ruby-build/contents/share/ruby-build"
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
VERSION_RE = re.compile(r"^\s*-\s+version:\s*[\"']?([^\"']+)[\"']?\s*$")
KEY_VALUE_RE = re.compile(r"^\s{4}([A-Za-z_][\w-]*):\s*(.+?)\s*$")


def semver_key(version: str) -> tuple[int, int, int]:
    return tuple(int(part) for part in version.split("."))  # type: ignore[return-value]


def series_for(version: str) -> str:
    major, minor, _patch = version.split(".")
    return f"{major}.{minor}"


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def find_versions_block(lines: list[str]) -> tuple[int, int]:
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == "versions:")
    except StopIteration as exc:
        raise ValueError("versions.yml is missing a top-level versions: block") from exc

    end = len(lines)
    for index in range(start + 1, len(lines)):
        line = lines[index]
        if line and not line.startswith((" ", "#")) and line.strip().endswith(":"):
            end = index
            while end > start + 1 and (
                lines[end - 1].strip() == "" or lines[end - 1].startswith("#")
            ):
                end -= 1
            break
    return start, end


def parse_versions(block_lines: list[str]) -> list[dict[str, str]]:
    versions: list[dict[str, str]] = []
    current: dict[str, str] | None = None

    for line in block_lines:
        version_match = VERSION_RE.match(line)
        if version_match:
            current = {"version": version_match.group(1)}
            versions.append(current)
            continue

        if current is None:
            continue

        key_value_match = KEY_VALUE_RE.match(line)
        if key_value_match:
            key, value = key_value_match.groups()
            current[key] = unquote(value)

    return versions


def fetch_ruby_build_versions() -> list[str]:
    with urllib.request.urlopen(RUBY_BUILD_API, timeout=30) as response:
        payload = json.load(response)

    versions = [item["name"] for item in payload if SEMVER_RE.match(item.get("name", ""))]
    return sorted(versions, key=semver_key, reverse=True)


def maintenance_label(value: str) -> str:
    return f"{value.capitalize()} Maintenance"


def format_versions_block(versions: list[dict[str, str]]) -> list[str]:
    lines = ["versions:\n"]
    grouped: dict[str, list[dict[str, str]]] = {}

    for version in versions:
        grouped.setdefault(series_for(version["version"]), []).append(version)

    for series in sorted(grouped, key=lambda item: tuple(int(part) for part in item.split(".")), reverse=True):
        entries = sorted(grouped[series], key=lambda item: semver_key(item["version"]), reverse=True)
        first = entries[0]
        lines.append(
            f"  # Ruby {series}.x series "
            f"({first['status'].capitalize()} - {maintenance_label(first['maintenance'])} "
            f"until {first['eol_date']})\n"
        )

        for entry in entries:
            lines.extend(
                [
                    f'  - version: "{entry["version"]}"\n',
                    f'    status: "{entry["status"]}"\n',
                    f'    priority: "{entry["priority"]}"\n',
                    f'    maintenance: "{entry["maintenance"]}"\n',
                    f'    eol_date: "{entry["eol_date"]}"\n',
                ]
            )
        lines.append("\n")

    return lines


def update_versions(versions: list[dict[str, str]], available: list[str]) -> tuple[list[dict[str, str]], list[str]]:
    today = date.today()
    supported = [
        deepcopy(version)
        for version in versions
        if date.fromisoformat(version["eol_date"]) > today
    ]
    removed = sorted(
        {version["version"] for version in versions} - {version["version"] for version in supported},
        key=semver_key,
        reverse=True,
    )

    available_by_series: dict[str, list[str]] = {}
    for version in available:
        available_by_series.setdefault(series_for(version), []).append(version)

    updated: list[dict[str, str]] = []
    added: list[str] = []
    tracked_series = sorted(
        {series_for(version["version"]) for version in supported},
        key=lambda item: tuple(int(part) for part in item.split(".")),
        reverse=True,
    )

    for series in tracked_series:
        series_entries = [
            version for version in supported if series_for(version["version"]) == series
        ]
        series_entries.sort(key=lambda item: semver_key(item["version"]), reverse=True)

        latest = available_by_series.get(series, [series_entries[0]["version"]])[0]
        if latest not in {entry["version"] for entry in series_entries}:
            template = deepcopy(series_entries[0])
            template["version"] = latest
            series_entries.insert(0, template)
            added.append(latest)

        series_entries.sort(key=lambda item: semver_key(item["version"]), reverse=True)
        for priority, entry in zip(["high", "medium", "low"], series_entries):
            entry["priority"] = priority

        updated.extend(series_entries[:3])

    messages = []
    if added:
        messages.append(f"Added Ruby versions: {', '.join(added)}")
    if removed:
        messages.append(f"Removed EOL Ruby versions: {', '.join(removed)}")
    if not messages:
        messages.append("Ruby versions are already up to date.")

    return updated, messages


def main() -> int:
    original_lines = VERSIONS_FILE.read_text().splitlines(keepends=True)
    start, end = find_versions_block(original_lines)
    versions = parse_versions(original_lines[start:end])

    if not versions:
        raise ValueError("versions.yml has no Ruby versions to update")

    updated_versions, messages = update_versions(versions, fetch_ruby_build_versions())
    tail_lines = original_lines[end:]
    while tail_lines and tail_lines[0].strip() == "":
        tail_lines = tail_lines[1:]

    updated_lines = (
        original_lines[:start]
        + format_versions_block(updated_versions)
        + tail_lines
    )

    VERSIONS_FILE.write_text("".join(updated_lines))

    for message in messages:
        print(message)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
