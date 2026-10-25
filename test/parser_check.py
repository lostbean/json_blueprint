"""Pinned JSONTestSuite and deterministic exact-value differential checks."""

from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import random
import re
import sys
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "test/oracle/json-test-suite"
SEED = 20261025
# JSONTestSuite permits these duplicate-name documents; our strict policy does not.
STRICT_DIFFERENCES = {
    "y_object_duplicated_key.json": "duplicate",
    "y_object_duplicated_key_and_value.json": "duplicate",
}
# Every implementation-defined case has an explicit expected outcome.
IMPLEMENTATION_CASES = {
    "i_number_double_huge_neg_exp.json": None,
    "i_number_huge_exp.json": None,
    "i_number_neg_int_huge_exp.json": None,
    "i_number_pos_double_huge_exp.json": None,
    "i_number_real_neg_overflow.json": None,
    "i_number_real_pos_overflow.json": None,
    "i_number_real_underflow.json": None,
    "i_number_too_big_neg_int.json": None,
    "i_number_too_big_pos_int.json": None,
    "i_number_very_big_negative_int.json": None,
    "i_object_key_lone_2nd_surrogate.json": "unicode_escape",
    "i_string_1st_surrogate_but_2nd_missing.json": "unicode_escape",
    "i_string_1st_valid_surrogate_2nd_invalid.json": "unicode_escape",
    "i_string_UTF-16LE_with_BOM.json": "utf8",
    "i_string_UTF-8_invalid_sequence.json": "utf8",
    "i_string_UTF8_surrogate_U+D800.json": "utf8",
    "i_string_incomplete_surrogate_and_escape_valid.json": "unicode_escape",
    "i_string_incomplete_surrogate_pair.json": "unicode_escape",
    "i_string_incomplete_surrogates_escape_valid.json": "unicode_escape",
    "i_string_invalid_lonely_surrogate.json": "unicode_escape",
    "i_string_invalid_surrogate.json": "unicode_escape",
    "i_string_invalid_utf-8.json": "utf8",
    "i_string_inverted_surrogates_U+1D11E.json": "unicode_escape",
    "i_string_iso_latin_1.json": "utf8",
    "i_string_lone_second_surrogate.json": "unicode_escape",
    "i_string_lone_utf8_continuation_byte.json": "utf8",
    "i_string_not_in_unicode_range.json": "utf8",
    "i_string_overlong_sequence_2_bytes.json": "utf8",
    "i_string_overlong_sequence_6_bytes.json": "utf8",
    "i_string_overlong_sequence_6_bytes_null.json": "utf8",
    "i_string_truncated-utf-8.json": "utf8",
    "i_string_utf16BE_no_BOM.json": "utf8",
    "i_string_utf16LE_no_BOM.json": "utf8",
    "i_structure_500_nested_arrays.json": None,
    "i_structure_UTF-8_BOM_empty_object.json": "syntax",
}


# Decimal's exponent range is finite; JSON Blueprint's Erlang Number exponent
# is not. Compare normalized symbolic decimals without expanding powers of ten.
@dataclass(frozen=True)
class ExactNumber:
    negative: bool
    coefficient: str
    exponent: int


def exact_number(token: str) -> ExactNumber:
    matched = re.fullmatch(
        r"(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?", token
    )
    if matched is None:
        raise ValueError("invalid number")
    negative, integer, fraction, exponent = matched.groups()
    fraction = fraction or ""
    digits = (integer + fraction).lstrip("0")
    if not digits:
        return ExactNumber(False, "0", 0)
    coefficient = digits.rstrip("0")
    scale = int(exponent or "0") - len(fraction) + len(digits) - len(coefficient)
    return ExactNumber(bool(negative), coefficient, scale)


def object_pairs(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError("duplicate")
        result[name] = value
    return result


def invalid_constant(token: str) -> object:
    raise ValueError(f"not a JSON number: {token}")


def exact_load(text: str) -> object:
    return json.loads(
        text,
        parse_int=exact_number,
        parse_float=exact_number,
        parse_constant=invalid_constant,
        object_pairs_hook=object_pairs,
    )


def semantics(value: object) -> object:
    """Compare JSON types as well as values (Python considers True == 1)."""
    if isinstance(value, dict):
        return (dict, tuple(sorted((k, semantics(v)) for k, v in value.items())))
    if isinstance(value, list):
        return (list, tuple(semantics(v) for v in value))
    return (type(value), value)


def generated_cases() -> dict[str, bytes]:
    rng = random.Random(SEED)
    alphabet = ["a", "雪", "🚀", "\\", '"', "\n", "\x00", "e\u0301"]

    def tree(depth: int) -> object:
        kind = rng.randrange(6 if depth else 4)
        if kind == 0:
            return None
        if kind == 1:
            return bool(rng.randrange(2))
        if kind == 2:
            return rng.randrange(-(10**40), 10**40)
        if kind == 3:
            return "".join(rng.choices(alphabet, k=rng.randrange(20)))
        if kind == 4:
            return [tree(depth - 1) for _ in range(rng.randrange(5))]
        return {f"k{i}雪": tree(depth - 1) for i in range(rng.randrange(5))}

    cases = {}
    for index in range(200):
        wire = json.dumps(tree(4), ensure_ascii=index % 2 == 0, separators=(",", ":"))
        variants = [wire, wire + "x", wire[:-1], "[" + wire + ",]"]
        for mutation, text in enumerate(variants):
            cases[f"generated_{index:03}_{mutation}.json"] = text.encode("utf-8")
    for index in range(100):
        coefficient = rng.randrange(-(10**50), 10**50)
        exponent = rng.randrange(-900, 900)
        cases[f"decimal_{index:03}.json"] = f"[{coefficient}e{exponent}]".encode()
    cases["generated_duplicate_escaped.json"] = b'{"a":1,"\\u0061":2}'
    return cases


def load_cases() -> dict[str, bytes]:
    provenance = json.loads((CORPUS / "provenance.json").read_text())
    archive = CORPUS / "corpus.zip"
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == provenance["sha256"]
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        assert len(names) == len(set(names)) == provenance["files"] == 318
        assert all(Path(name).name == name and name.endswith(".json") for name in names)
        cases = {name: bundle.read(name) for name in names}
    assert {name for name in cases if name.startswith("i_")} == set(
        IMPLEMENTATION_CASES
    )
    assert set(STRICT_DIFFERENCES) <= cases.keys()
    cases.update(generated_cases())
    return cases


def check_case(name: str, raw: bytes, row: dict[str, object], target: str) -> None:
    expected = STRICT_DIFFERENCES.get(name)
    if name.startswith("i_"):
        expected = IMPLEMENTATION_CASES[name]
    # The portable JavaScript representation still requires an exact native
    # integer exponent, independently of application admission limits.
    if target == "javascript" and name == "i_number_huge_exp.json":
        expected = "number"
    if target == "erlang" and expected == "unicode_escape":
        expected = "syntax"
    if name.startswith("n_"):
        assert isinstance(row.get("rejected"), str), f"accepted invalid input: {name}"
        return
    if expected is not None:
        assert row.get("rejected") == expected, (
            f"{name}: expected {expected}, got {row}"
        )
        return
    try:
        original = exact_load(raw.decode("utf-8"))
    except ValueError:
        assert not name.startswith(("y_", "i_")), (
            f"oracle disagrees with corpus: {name}"
        )
        assert "rejected" in row, f"accepted malformed generated input: {name}"
        return
    assert isinstance(row.get("rendered"), str), f"rejected valid input: {name}: {row}"
    assert semantics(exact_load(row["rendered"])) == semantics(original), name


def main() -> None:
    # The pinned suite includes a valid 500-level structure. This affects only
    # the Python oracle traversal, not parser policy.
    sys.setrecursionlimit(10000)
    cases = load_cases()
    with tempfile.TemporaryDirectory(prefix="blueprint-parser-") as directory:
        for name, raw in cases.items():
            (Path(directory) / name).write_bytes(raw)
        for target in ("erlang", "javascript"):
            result = subprocess.run(
                ["gleam", "run", "--target", target, "-m", "parser_corpus_runner"],
                cwd=ROOT,
                env={**os.environ, "BLUEPRINT_PARSER_CORPUS": directory},
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode:
                raise SystemExit(result.stdout + result.stderr)
            rows = [
                json.loads(line) for line in result.stdout.split("\n") if line.strip()
            ]
            assert Counter(row["name"] for row in rows) == Counter(cases.keys()), target
            for row in rows:
                check_case(row["name"], cases[row["name"]], row, target)
            print(
                f"PASS: {target}: 318 upstream + {len(cases) - 318} generated parser cases (seed {SEED})"
            )


if __name__ == "__main__":
    main()
