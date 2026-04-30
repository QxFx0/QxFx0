#!/usr/bin/env python3
"""Unit tests for scripts/import_brain_kb.py."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "import_brain_kb.py"
SCHEMA = ROOT / "spec" / "sql" / "lexicon" / "schema.sql"

sys.path.insert(0, str(ROOT / "scripts"))
from import_brain_kb import extract_tokens  # noqa: E402


class TestExtractTokens(unittest.TestCase):
    def test_extract_tokens_filters_noise(self):
        text = "Что делать при тревоге и усталости, если ничего не хочется?"
        tokens = extract_tokens(text)
        self.assertIn("тревоге", tokens)
        self.assertIn("хочется", tokens)
        self.assertNotIn("что", tokens)
        self.assertNotIn("если", tokens)


class TestCliIntegration(unittest.TestCase):
    def test_cli_generates_reviewed_seed(self):
        sample_units = [
            {
                "id": "u1",
                "layer": "identity",
                "kind": "claim",
                "text": "Я держу контекст и разбираю тревогу по шагам.",
                "topic": ["тревога", "контекст"],
                "triggers": ["тревога", "шаги"],
                "usage": {"weight": 1.0},
            },
            {
                "id": "u2",
                "layer": "dialogue",
                "kind": "claim",
                "text": "При усталости полезен короткий шаг и пауза.",
                "topic": ["усталость"],
                "triggers": ["усталость", "пауза"],
                "usage": {"weight": 0.9},
            },
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            input_path = tmp / "brain_kb.jsonl"
            output_seed = tmp / "seed_brain_kb_reviewed.sql"

            with input_path.open("w", encoding="utf-8") as f:
                for unit in sample_units:
                    f.write(json.dumps(unit, ensure_ascii=False) + "\n")

            cmd = [
                sys.executable,
                str(SCRIPT),
                "--input",
                str(input_path),
                "--schema",
                str(SCHEMA),
                "--output-seed",
                str(output_seed),
                "--top-n",
                "20",
                "--min-count",
                "1",
                "--min-score",
                "0.1",
            ]
            subprocess.run(cmd, check=True, cwd=ROOT)

            seed_text = output_seed.read_text(encoding="utf-8")
            self.assertIn("brain-kb-reviewed", seed_text)
            self.assertTrue(
                any(needle in seed_text for needle in ("'шаг'", "'тревога'", "'усталость'")),
                "expected at least one salient noun candidate in generated seed",
            )


if __name__ == "__main__":
    unittest.main()
