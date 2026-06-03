#!/usr/bin/env python3
import argparse
import json
import sys


REQUIRED_FIELDS = [
    "trcRequestId",
    "trcShadowSnapshotId",
    "trcRuntimeMode",
    "trcShadowPolicy",
    "trcLocalRecoveryPolicy",
    "trcRecoveryCause",
    "trcRecoveryStrategy",
    "trcRecoveryEvidence",
    "trcSemanticIntrospectionEnabled",
    "trcWarnMorphologyFallbackEnabled",
    "trcAuthorityClass",
    "trcTruthContractStatus",
    "trcAssemblyPath",
    "trcReplayProvenanceStatus",
    "trcPreSafetyRenderedRaw",
    "trcRenderedAfterRebind",
    "trcArtifactManifest",
]


def load_trace(raw: str) -> dict:
    if not raw.strip():
        raise SystemExit("empty replay trace payload")
    try:
        trace = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid replay trace json: {exc}") from exc
    if not isinstance(trace, dict):
        raise SystemExit("replay trace payload must be a JSON object")
    return trace


def validate_trace(trace: dict) -> None:
    missing = [name for name in REQUIRED_FIELDS if name not in trace]
    if missing:
        raise SystemExit("missing replay envelope fields: " + ",".join(missing))

    for text_field in ("trcRuntimeMode", "trcShadowPolicy", "trcLocalRecoveryPolicy"):
        value = trace.get(text_field)
        if not isinstance(value, str) or not value:
            raise SystemExit(f"invalid replay envelope text field: {text_field}")

    for optional_text_field in ("trcRecoveryCause", "trcRecoveryStrategy"):
        value = trace.get(optional_text_field)
        if value is not None and not isinstance(value, str):
            raise SystemExit(f"invalid replay envelope optional text field: {optional_text_field}")

    recovery_evidence = trace.get("trcRecoveryEvidence")
    if not isinstance(recovery_evidence, list) or not all(isinstance(item, str) for item in recovery_evidence):
        raise SystemExit("invalid replay envelope evidence field: trcRecoveryEvidence")

    for bool_field in ("trcSemanticIntrospectionEnabled", "trcWarnMorphologyFallbackEnabled"):
        if not isinstance(trace.get(bool_field), bool):
            raise SystemExit(f"invalid replay envelope bool field: {bool_field}")



def main() -> None:
    parser = argparse.ArgumentParser(description="Validate replay trace envelope fields")
    parser.add_argument("--json", dest="json_payload", help="Replay trace JSON payload")
    args = parser.parse_args()

    raw = args.json_payload if args.json_payload is not None else sys.stdin.read()
    trace = load_trace(raw)
    validate_trace(trace)
    print("replay trace OK")


if __name__ == "__main__":
    main()
