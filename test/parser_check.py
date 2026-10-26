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
    value = json.loads(
        text,
        parse_int=exact_number,
        parse_float=exact_number,
        parse_constant=invalid_constant,
        object_pairs_hook=object_pairs,
    )
    scalar_strings(value)
    return value


def scalar_strings(value: object) -> None:
    """Python permits lone escaped surrogates; our declared profile does not."""
    if isinstance(value, str):
        if any(0xD800 <= ord(char) <= 0xDFFF for char in value):
            raise ValueError("non-scalar string")
    elif isinstance(value, list):
        for child in value:
            scalar_strings(child)
    elif isinstance(value, dict):
        for key, child in value.items():
            scalar_strings(key)
            scalar_strings(child)


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
    cases.update(boundary_cases())
    return cases


def boundary_cases() -> dict[str, bytes]:
    """Finite constructed boundaries, independent of Blueprint's parser code."""
    cases = {}
    # Every literal control byte rejects, while its escaped spelling accepts.
    for code in range(32):
        cases[f"control_literal_{code:02}.json"] = b'"' + bytes([code]) + b'"'
        cases[f"control_escaped_{code:02}.json"] = f'"\\u{code:04x}"'.encode()
    scalars = [
        0,
        31,
        32,
        127,
        128,
        0x7FF,
        0x800,
        0xD7FF,
        0xE000,
        0xFFFF,
        0x10000,
        0x10FFFF,
    ]
    for code in scalars:
        for escaped in (False, True):
            cases[f"scalar_{code:x}_{escaped}.json"] = json.dumps(
                {chr(code): [chr(code)]}, ensure_ascii=escaped
            ).encode("utf-8")
    # Raw valid scalars and escaped names denote the same key, including pairs.
    for index, key in enumerate(["a", "雪", "🚀", "\x00", "\n", '"', "\\"]):
        literal = json.dumps(key, ensure_ascii=False)
        escaped = (
            '"'
            + "".join(
                f"\\u{int.from_bytes(key.encode('utf-16-be')[i : i + 2], 'big'):04x}"
                for i in range(0, len(key.encode("utf-16-be")), 2)
            )
            + '"'
        )
        cases[f"duplicate_equivalent_nested_{index}.json"] = (
            '[{"outer":{' + literal + ":1," + escaped + ":2}}]"
        ).encode()
    cases["distinct_normalization_forms.json"] = '{"é":1,"é":2}'.encode()
    # UTF-8 continuation, overlong, surrogate, out-of-range and truncated forms.
    bad_utf8 = [
        b"\x80",
        b"\xc0\xaf",
        b"\xc1\xbf",
        b"\xe0\x80\xaf",
        b"\xed\xa0\x80",
        b"\xed\xbf\xbf",
        b"\xf0\x80\x80\xaf",
        b"\xf4\x90\x80\x80",
        b"\xf5\x80\x80\x80",
        b"\xff",
        b"\xfe",
        b"\xc2",
        b"\xe2",
        b"\xe2\x82",
        b"\xf0",
        b"\xf0\x9f",
        b"\xf0\x9f\x92",
    ]
    for index, raw in enumerate(bad_utf8):
        cases[f"utf8_value_{index}.json"] = b'["' + raw + b'"]'
        cases[f"utf8_key_{index}.json"] = b'{"' + raw + b'":0}'
    escaped_invalid = [
        "\\ud800",
        "\\udbff",
        "\\udc00",
        "\\udfff",
        "\\ud800\\ud800",
        "\\udc00\\ud800",
        "\\udbffx",
        "\\udbff\\ue000",
    ]
    for index, raw in enumerate(escaped_invalid):
        cases[f"surrogate_value_{index}.json"] = ('["' + raw + '"]').encode()
        cases[f"surrogate_key_{index}.json"] = ('{"' + raw + '":0}').encode()
    # Check every byte-prefix, including cuts through UTF-8 and escape tokens.
    documents = [
        '{"雪":["🚀","\\uD83D\\uDE80",true,null,-1.00000000000000001e+2]}'.encode(),
        b'[{"a":"\\"\\\\\\n"},[0,1e-400,9007199254740993]]',
    ]
    for document_index, document in enumerate(documents):
        for end in range(len(document) + 1):
            cases[f"prefix_{document_index}_{end:03}.json"] = document[:end]
    numbers = [
        "1.00000000000000001",
        "9007199254740993",
        "-0e999999999",
        "1e999999999",
        "1e-999999999",
        "1e1201",
        "1e-1201",
        "4.9406564584124654e-324",
        "1.7976931348623157e308",
        "1" * 1100,
        "0." + "1" * 1100,
        "1e+" + "0" * 1000 + "2",
    ]
    for index, token in enumerate(numbers):
        cases[f"number_boundary_{index}.json"] = ("[" + token + "]").encode()
    for depth in (65, 100, 256, 500):
        cases[f"nested_valid_{depth}.json"] = b"[" * depth + b"0" + b"]" * depth
    # Deliberately invalid, so every target must return an error (never crash).
    cases["n_generated_deep_unclosed.json"] = b"[" * 20000
    cases["n_generated_deep_trailing_comma.json"] = b"[" * 20000 + b"0," + b"]" * 20000
    wide = b"[" + b",".join([b"0"] * 10000)
    cases["wide_valid.json"] = wide + b"]"
    cases["n_generated_wide_unclosed.json"] = wide
    cases["n_generated_wide_trailing_comma.json"] = wide + b",]"
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
    if name.startswith("duplicate_equivalent_nested_"):
        expected = "duplicate"
    elif name.startswith(("utf8_value_", "utf8_key_")):
        expected = "utf8"
    elif name.startswith(("surrogate_value_", "surrogate_key_")):
        expected = "unicode_escape"
    if name.startswith("i_"):
        expected = IMPLEMENTATION_CASES[name]
    # The JavaScript representation still requires an exact native
    # integer exponent, independently of application admission limits.
    if target == "javascript" and name == "i_number_huge_exp.json":
        expected = "number"
    if expected == "unicode_escape":
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
