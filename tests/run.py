#!/usr/bin/env python3
"""Compile the shipped single file, then execute its real policy/runtime in Luau.

Use LUAU_BIN and LUAU_COMPILE_BIN, or put luau / luau-compile on PATH.
Tests never contact Roblox, the Finder, the key endpoint, or Discord.
"""
from __future__ import annotations

import os
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "UNKNOWN.lua"


def binary(name: str, variable: str) -> str:
    result = os.environ.get(variable) or shutil.which(name)
    # Convenience for this Arena workspace; not a project dependency.
    local_build = Path.home() / ".cache/unknown-luau/luau-0.746" / name
    if not result and local_build.is_file():
        result = str(local_build)
    if not result:
        raise SystemExit(f"Install the Luau CLI and set {variable} (missing {name}).")
    return result


def main() -> None:
    source = SOURCE.read_text()
    forbidden = {
        "character transform write": r"\b(?:root|character|hrp)\s*\.(?:CFrame|Position)\s*=",
        "pivot teleport": r":\s*(?:PivotTo|SetPrimaryPartCFrame)\s*\(",
        "forced death/respawn": r"\b(?:BreakJoints|LoadCharacter|TakeDamage)\s*\(",
        "legacy warp helper": r"\bparkAt\s*\(",
        "shared network lock": r"\bnetworkBusy\b",
        "old backup loader": r"unknown-safe-copy-2026-11-07",
    }
    for label, pattern in forbidden.items():
        assert not re.search(pattern, source, re.I), label
    assert "world:SetAttribute('ClientObbyAntiTp', false)" in source
    assert "AgentCanJump = false" in source
    assert source.count("eggState.CarryFieldEgg(uid, slotKey)") == 1
    assert source.count("eggState.PlantEgg(uid, CFrame.new(0, 0, 0))") == 1
    print("PASS static movement / single-call / loader guards", flush=True)
    protected = json.loads((ROOT / "tests/preservation.json").read_text())
    for region in protected["regions"]:
        start = source.index(region["start"])
        end = source.index(region["end"], start)
        actual = hashlib.sha256(source[start:end].encode()).hexdigest()
        assert actual == region["sha256"], f"Protected baseline changed: {region['name']}"
    assert source.count("deps.panel.Position = UDim2.fromOffset(x, y)") == 1
    assert "panel.Position =" not in source.replace("deps.panel.Position =", "")
    assert "state.autoJoin and 0.2 or 0.8" in source
    assert "if not state.autoJoin and not ui.visible then interval = 2 end" in source
    assert "local retryBeat = game:GetService('RunService').Heartbeat:Connect" not in source
    assert "publishedFingerprints[laneKey] ~= fingerprint" in source
    print("PASS 7 protected core blocks + single position owner / unchanged cadence", flush=True)


    compiler = binary("luau-compile", "LUAU_COMPILE_BIN")
    luau = binary("luau", "LUAU_BIN")
    subprocess.run([compiler, str(SOURCE)], stdout=subprocess.DEVNULL, check=True)
    print("PASS full UNKNOWN.lua Luau compilation (including register limits)", flush=True)
    mock = (ROOT / "tests/roblox_mock.luau").read_text()
    policy = source.split("-- BEGIN POLICY", 1)[1].split("\n", 1)[1].split("-- END POLICY", 1)[0]
    suites = {
        "policy": mock + "\n" + policy + "\n" + (ROOT / "tests/policy_spec.luau").read_text(),
        "integration": mock + "\n" + policy + "\nlocal function executeScript()\n" + source
        + "\nend\n" + (ROOT / "tests/integration_spec.luau").read_text(),
        "ui": mock + "\n" + policy + "\nlocal function executeScript()\n" + source
        + "\nend\n" + (ROOT / "tests/ui_spec.luau").read_text(),
        "perf": mock + "\n" + policy + "\nlocal function executeScript()\n" + source
        + "\nend\nlocal PERF_ENFORCE = true\n" + (ROOT / "tests/perf_spec.luau").read_text(),
    }
    with tempfile.TemporaryDirectory(prefix="unknown-luau-") as scratch:
        for name, content in suites.items():
            path = Path(scratch) / f"{name}.luau"
            path.write_text(content)
            subprocess.run([luau, str(path)], check=True)
    print("All offline checks passed. Roblox/server behavior still needs an in-game smoke test.", flush=True)


if __name__ == "__main__":
    main()
