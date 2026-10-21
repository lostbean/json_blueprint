"""Independent Decimal/Fraction oracle for the public Erlang number API."""

from decimal import Decimal
from fractions import Fraction
import json
import math
from pathlib import Path
import re
import struct
import subprocess


ROOT = Path(__file__).resolve().parent.parent
NUMBER = re.compile(r"-?(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\Z")
REQUIRED_TOKENS = {
    "+1",
    "01",
    "1.",
    ".1",
    "1e",
    "1e+",
    "--1",
    "1.2.3",
    "-0",
    "0",
    "1.0",
    "10e-1",
    "100e-2",
    "123.45",
    "1.2300e2",
    "0.5",
    "0.1",
    "0.125",
    "9007199254740992",
    "9007199254740993",
    "1e400",
    "1e-400",
    "1.7976931348623159e308",
}
REQUIRED_BITS = {
    "0000000000000000",
    "8000000000000000",
    "3fe0000000000000",
    "3fb999999999999a",
    "0000000000000001",
    "7fefffffffffffff",
}
REQUIRED_INTEGERS = {"0", "12", "120", "-120", "9007199254740993"}


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


def exact(token):
    require(
        isinstance(token, str) and NUMBER.fullmatch(token), f"invalid witness {token!r}"
    )
    return Fraction(Decimal(token))


def bits(value):
    return struct.pack(">d", value).hex()


def float_from_bits(value):
    require(
        isinstance(value, str) and re.fullmatch(r"[0-9a-f]{16}", value),
        "invalid float bits",
    )
    return struct.unpack(">d", bytes.fromhex(value))[0]


def canonical(token):
    value = Decimal(token)
    if not value:
        return "0"
    sign, digits, exponent = value.as_tuple()
    coefficient = "".join(str(digit) for digit in digits)
    trimmed = coefficient.rstrip("0")
    exponent += len(coefficient) - len(trimmed)
    scientific_exponent = exponent + len(trimmed) - 1
    mantissa = trimmed[0] + ("." + trimmed[1:] if len(trimmed) > 1 else "")
    return (
        ("-" if sign else "")
        + mantissa
        + (f"e{scientific_exponent}" if scientific_exponent else "")
    )


def parse_status(token, limits):
    token_bytes = len(token.encode("utf-8"))
    if token_bytes > limits["parse_max_token_bytes"]:
        return "token_too_long"
    match = NUMBER.fullmatch(token)
    if not match:
        return "invalid_syntax"
    whole, fraction, written_exponent = match.groups()
    coefficient = whole + (fraction or "")
    if len(coefficient) > limits["parse_max_significand_digits"]:
        return "significand_too_long"
    exponent = int(written_exponent or "0")
    # A bounded written-exponent accumulator also protects all-zero values.
    if abs(exponent) > limits["parse_max_abs_exponent"] + token_bytes:
        return "exponent_out_of_range"
    nonzero = coefficient.lstrip("0")
    normalized_exponent = (
        exponent - len(fraction or "") + len(nonzero) - len(nonzero.rstrip("0"))
        if nonzero
        else 0
    )
    if abs(normalized_exponent) > limits["parse_max_abs_exponent"]:
        return "exponent_out_of_range"
    return "accepted"


def check_parse(row, limits):
    token = row["token"]
    status = parse_status(token, limits)
    require(row["status"] == status, f"parse {token}: {row['status']} != {status}")
    if status != "accepted":
        for key in (
            "canonical",
            "integer",
            "int_value",
            "float_bits_hex",
            "float_exact_decimal",
        ):
            require(row[key] is None, f"rejected token retained {key}: {token}")
        require(row["int_status"] == row["float_status"] == "not_applicable", token)
        return
    value = exact(token)
    require(
        row["canonical"] == canonical(token), f"canonical {token}: {row['canonical']}"
    )
    require(
        type(row["integer"]) is bool and row["integer"] == (value.denominator == 1),
        f"integrality {token}",
    )
    if value.denominator != 1:
        int_status = "fractional"
    elif len(str(abs(value.numerator))) > limits["int_projection_max_digits"]:
        int_status = "digit_limit"
    else:
        int_status = "exact"
    require(row["int_status"] == int_status, f"integer projection {token}")
    require(
        row["int_value"] == (str(value.numerator) if int_status == "exact" else None),
        f"integer witness {token}",
    )
    candidate = float(token)
    if not math.isfinite(candidate):
        float_status = "overflow"
    elif candidate == 0 and value:
        float_status = "underflow"
    elif Fraction.from_float(candidate) != value:
        float_status = "inexact"
    else:
        float_status = "exact"
    require(
        row["float_status"] == float_status,
        f"float projection {token}: {row['float_status']} != {float_status}",
    )
    if float_status == "exact":
        returned = float_from_bits(row["float_bits_hex"])
        require(
            math.isfinite(returned) and Fraction.from_float(returned) == value,
            f"native float {token}",
        )
        require(exact(row["float_exact_decimal"]) == value, f"float decimal {token}")
        # The mathematical representation deliberately forgets negative zero.
        require(
            bits(returned) == bits(candidate if value else 0.0),
            f"float bit witness {token}",
        )
    else:
        require(
            row["float_bits_hex"] is None and row["float_exact_decimal"] is None,
            f"failed float witness {token}",
        )


def check_rows(rows):
    require(rows and rows[0]["kind"] == "limits", "missing limits row")
    keys = (
        "parse_max_token_bytes",
        "parse_max_significand_digits",
        "parse_max_abs_exponent",
        "int_projection_max_digits",
    )
    limits = {key: int(rows[0][key]) for key in keys}
    require(all(value > 0 for value in limits.values()), "invalid oracle profile")
    tokens, float_inputs, integer_inputs, orders, statuses = (
        set(),
        set(),
        set(),
        set(),
        set(),
    )
    for row in rows[1:]:
        kind = row["kind"]
        if kind == "parse":
            require(row["token"] not in tokens, "duplicate parse fixture")
            tokens.add(row["token"])
            check_parse(row, limits)
            statuses.add(row["status"])
        elif kind == "compare":
            left, right = exact(row["left"]), exact(row["right"])
            expected = (
                "less" if left < right else "greater" if left > right else "equal"
            )
            require(row["order"] == expected, f"comparison {row}")
            orders.add(expected)
        elif kind == "from_int":
            raw = row["input"]
            require(
                raw not in integer_inputs and re.fullmatch(r"-?(0|[1-9][0-9]*)", raw),
                "invalid integer fixture",
            )
            integer_inputs.add(raw)
            require(
                row["canonical"] == canonical(raw), f"integer origin canonical {raw}"
            )
            expected_status = (
                "exact"
                if len(raw.lstrip("-")) <= limits["int_projection_max_digits"]
                else "digit_limit"
            )
            require(
                row["int_status"] == expected_status, f"integer origin projection {raw}"
            )
            require(
                row["int_value"] == (raw if expected_status == "exact" else None),
                f"integer origin witness {raw}",
            )
        elif kind == "from_float":
            raw = row["input_hex"]
            require(raw not in float_inputs, "duplicate float fixture")
            float_inputs.add(raw)
            value = float_from_bits(raw)
            require(
                math.isfinite(value) and row["status"] == "accepted",
                f"float origin {raw}",
            )
            require(
                exact(row["canonical"]) == Fraction.from_float(value),
                f"float origin decimal {raw}",
            )
            require(
                row["canonical"] == canonical(row["canonical"]),
                f"float origin canonical {raw}",
            )
            require(
                row["roundtrip_bits_hex"] == (raw if value else "0000000000000000"),
                f"float roundtrip {raw}",
            )
        else:
            raise AssertionError(f"unexpected number row {kind}")
    require(REQUIRED_TOKENS <= tokens, f"missing tokens {REQUIRED_TOKENS - tokens}")
    require(
        REQUIRED_BITS <= float_inputs,
        f"missing float fixtures {REQUIRED_BITS - float_inputs}",
    )
    require(
        REQUIRED_INTEGERS <= integer_inputs,
        f"missing integer fixtures {REQUIRED_INTEGERS - integer_inputs}",
    )
    require(orders == {"less", "equal", "greater"}, "incomplete comparisons")
    require(
        statuses
        == {
            "accepted",
            "invalid_syntax",
            "token_too_long",
            "significand_too_long",
            "exponent_out_of_range",
        },
        "incomplete parse statuses",
    )
    return len(rows) - 1


def main():
    result = subprocess.run(
        ["gleam", "run", "--target", "erlang", "-m", "number_oracle_runner"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    try:
        rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        count = check_rows(rows)
    except (AssertionError, KeyError, ValueError) as error:
        raise SystemExit(f"FAIL: exact-number oracle: {error}") from error
    print(f"PASS: {count} independent exact-number cases")


if __name__ == "__main__":
    main()
