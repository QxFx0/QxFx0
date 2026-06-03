#!/usr/bin/env python3
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def require_text(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{path}: missing required text markers: {missing}")


def require_json_fields(path: Path, fields: list[str]) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    missing = [field for field in fields if field not in data]
    if missing:
        raise SystemExit(f"{path}: missing required json fields: {missing}")


def main() -> None:
    runtime_contract = ROOT / "docs" / "runtime_deployment_contract.md"
    worker_protocol = ROOT / "docs" / "worker_protocol_v1.md"
    resource_matrix = ROOT / "docs" / "resource_contract_matrix.md"
    state_contract = ROOT / "docs" / "state_persistence_contract.md"
    singleton_register = ROOT / "docs" / "singleton_register.md"
    hash_note = ROOT / "docs" / "hash_migration_note.md"
    readme = ROOT / "README.md"
    interop = ROOT / "docs" / "interop" / "README.md"
    ci_profile = ROOT / "docs" / "CI_PRODUCTION_PROFILE.md"
    dockerfile = ROOT / "Dockerfile"
    flake = ROOT / "flake.nix"
    nix_module = ROOT / "nix" / "module.nix"
    embedding_runtime = ROOT / "src" / "QxFx0" / "Semantic" / "Embedding" / "Runtime.hs"
    external_llm = ROOT / "src" / "QxFx0" / "Bridge" / "ExternalLLM.hs"

    require_text(
        runtime_contract,
        "Primary blocking runtime surface: installed Cabal artifact",
        "python3 -m unittest discover -s test -p 'test_*.py'",
        "docs/worker_protocol_v1.md",
        "docs/resource_contract_matrix.md",
        "docs/singleton_register.md",
        "docs/hash_migration_note.md",
        "docs/state_persistence_contract.md",
        "QXFX0_DB",
        "QXFX0_DB_PATH",
        "QXFX0_RESOURCE_ROOT",
        "QXFX0_CONCEPTS_PATH",
        "Official endpoint allowlist",
        "QXFX0_LLM_TIMEOUT_MS",
        "4096` chars",
        "16384` bytes",
        "65536` bytes",
        "GF map load failure is fail-closed for authoritative GF linearization",
        "gf_default_lexeme_explicit",
        "container artifact",
        "Nix artifact",
    )
    require_text(
        worker_protocol,
        '"command": "hello"',
        '"protocol_version": "1"',
        "protocol_version_mismatch",
        "unknown_command",
        "malformed_authenticated_request",
        "test/fixtures/worker_protocol_v1/",
    )
    require_text(
        resource_matrix,
        "GF map (`lexicon_funmap.tsv`)",
        "forms_by_surface.json",
        "Agda witness / spec",
        "Nix policy (`concepts.nix`) + evaluator",
        "gf_map_unavailable:*",
        "gf_default_lexeme",
        "optional_degraded",
    )
    require_text(
        state_contract,
        "dialogue_state",
        "__system_state__",
        "turn_quality.replay_trace_json",
        "critical durable state",
        "runtime cache",
        "governance projection",
    )
    require_text(readme, "docs/runtime_deployment_contract.md")
    require_text(readme, "check_runtime_contract.py")
    require_text(readme, "check_concepts_schema.py")
    require_text(
        interop,
        "docs/runtime_deployment_contract.md",
        "docs/worker_protocol_v1.md",
        "docs/resource_contract_matrix.md",
    )
    require_text(dockerfile, "ENV QXFX0_DB=/data/qxfx0.db")
    require_text(flake, '"QXFX0_DB=/data/qxfx0.db"', "QXFX0_DB:-''${QXFX0_DB_PATH:-qxfx0.db}")
    require_text(nix_module, "QXFX0_DB = cfg.dbPath;", "QXFX0_CONCEPTS_PATH = cfg.conceptsPath;", "path = [ pkgs.python3 ];")

    if "sharedEmbeddingManager" in embedding_runtime.read_text(encoding="utf-8"):
        raise SystemExit("Embedding runtime still contains sharedEmbeddingManager singleton")
    if "sharedExternalLlmManager" in external_llm.read_text(encoding="utf-8"):
        raise SystemExit("ExternalLLM still contains sharedExternalLlmManager singleton")

    # Extended CI doc must match the workflow: no push-to-main trigger.
    profile_text = ci_profile.read_text(encoding="utf-8")
    if "Push to `main` branch only" in profile_text:
        raise SystemExit(
            "docs/CI_PRODUCTION_PROFILE.md still claims push-to-main extended trigger"
        )
    if "Job 3: Granular Fast Gates (`build-test`)" in profile_text:
        raise SystemExit(
            "docs/CI_PRODUCTION_PROFILE.md still describes removed build-test workflow job"
        )
    require_text(
        ci_profile,
        "Current Workflow Graph",
        "core-contract",
        "extended-contract",
        "Current Test Suite Graph",
        "qxfx0-test-unit",
        "qxfx0-test-property",
        "qxfx0-test-integration",
        "qxfx0-test-fast",
        "qxfx0-test-slow",
        "StatePersistence",
        "HttpRuntime",
    )

    python_gap = ROOT / "docs" / "PYTHON_TEST_GAP.md"
    release_readiness = ROOT / "docs" / "release_readiness.md"
    extended_runbook = ROOT / "docs" / "EXTENDED_CONTRACT_RUNBOOK.md"

    require_text(
        python_gap,
        "scripts/check_runtime_contract.py",
        "scripts/check_concepts_schema.py",
    )
    require_text(
        release_readiness,
        "CONTRACT_VERDICT: PROD_GO",
        "CONTRACT_VERDICT: FULL_SCIENTIFIC_GO",
        "tiered contract verdicts are canonical",
    )
    require_text(
        extended_runbook,
        "/tmp/gf-install/usr/lib/libpgf.so*",
        "/tmp/gf-install/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}",
    )

    fixtures_dir = ROOT / "test" / "fixtures" / "worker_protocol_v1"
    require_json_fields(fixtures_dir / "handshake_request.json", ["command", "protocol_version", "capabilities"])
    require_json_fields(fixtures_dir / "handshake_ok_response.json", ["status", "command", "protocol_version", "protocol_match", "capabilities"])
    require_json_fields(fixtures_dir / "version_mismatch_response.json", ["status", "error", "protocol_version", "requested_protocol_version", "restart_required"])
    require_json_fields(fixtures_dir / "unknown_command_response.json", ["status", "error", "restart_required"])
    require_json_fields(fixtures_dir / "malformed_authenticated_request_response.json", ["error", "error_code", "result_unknown", "session_valid", "restart_required"])

    print("runtime contract OK")


if __name__ == "__main__":
    main()
