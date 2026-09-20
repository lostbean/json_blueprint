import { Ok, Error, List } from "./gleam.mjs";

export function byte_length(value) {
  return new TextEncoder().encode(value).length;
}

export function byte_codes(value) {
  return List.fromArray(Array.from(new TextEncoder().encode(value)));
}

export function ascii_string(bytes) {
  let s = "";
  for (const b of bytes) {
    s += String.fromCharCode(b);
  }
  return s;
}

export function integer_to_string(value) {
  return value.toString();
}

export function validate_native_int(
  value,
  onNonFinite,
  onFractional,
  onUnsupported
) {
  if (typeof value !== "number" && typeof value !== "bigint") {
    return new Error(onFractional);
  }
  if (typeof value === "bigint") {
    if (value < -9007199254740991n || value > 9007199254740991n) {
      return new Error(onUnsupported);
    }
    return new Ok(value.toString());
  }
  if (!Number.isFinite(value)) {
    return new Error(onNonFinite);
  }
  if (!Number.isInteger(value)) {
    return new Error(onFractional);
  }
  if (value < Number.MIN_SAFE_INTEGER || value > Number.MAX_SAFE_INTEGER) {
    return new Error(onUnsupported);
  }
  return new Ok(value.toString());
}

export function integer_divide(dividend, divisor) {
  return Math.trunc(dividend / divisor);
}

export function integer_remainder(dividend, divisor) {
  return dividend % divisor;
}

export function float_parts(value) {
  const buf = new ArrayBuffer(8);
  const view = new DataView(buf);
  view.setFloat64(0, value);
  const hi = view.getUint32(0);
  const lo = view.getUint32(4);
  const sign = (hi & 0x80000000) !== 0;
  const exp = (hi >>> 20) & 0x7ff;
  const fracHi = hi & 0xfffff;
  if (exp === 0x7ff) {
    return new Error(undefined);
  }
  if (exp === 0 && fracHi === 0 && lo === 0) {
    return new Ok([sign, 0, 0]);
  }
  if (exp === 0) {
    const sig = fracHi * 0x100000000 + lo;
    return new Ok([sign, sig, -1074]);
  }
  const sig = (0x100000 | fracHi) * 0x100000000 + lo;
  const exp2 = exp - 1023 - 52;
  return new Ok([sign, sig, exp2]);
}

export function parse_float_candidate(token, onValue, onOverflow, onInvalid) {
  if (!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/.test(token)) {
    return onInvalid;
  }
  const val = Number(token);
  if (!Number.isFinite(val)) {
    return onOverflow;
  }
  return onValue(val);
}

export function float_to_decimal(significand, exponent2) {
  let coeff;
  let exp10;
  const sig = BigInt(significand);
  const exp2 = BigInt(exponent2);
  if (exponent2 >= 0) {
    coeff = sig * (2n ** exp2);
    exp10 = 0;
  } else {
    coeff = sig * (5n ** (-exp2));
    exp10 = exponent2;
  }
  const digits = Array.from(new TextEncoder().encode(coeff.toString()));
  return [List.fromArray(digits), exp10];
}

export function decimal_equals_binary(decDigits, decExp, binSig, binExp) {
  let decStr = "";
  for (const code of decDigits) {
    decStr += String.fromCharCode(code);
  }
  let decSignificand = BigInt(decStr);
  let binSignificand = BigInt(binSig);
  let binExponent = binExp;

  while (binSignificand > 0n && (binSignificand % 2n) === 0n) {
    binSignificand = binSignificand / 2n;
    binExponent += 1;
  }

  if (decExp >= 0 && binExponent >= 0) {
    return (
      decSignificand * (10n ** BigInt(decExp)) ===
      binSignificand * (2n ** BigInt(binExponent))
    );
  } else if (decExp >= 0 || binExponent >= 0) {
    return false;
  } else {
    const decDenomExp = BigInt(-decExp);
    const binDenomExp = BigInt(-binExponent);
    return (
      decSignificand * (2n ** binDenomExp) ===
      binSignificand * (2n ** decDenomExp) * (5n ** decDenomExp)
    );
  }
}

export function project_native_int(negative, digits, exponent10) {
  let str = "";
  for (const code of digits) {
    str += String.fromCharCode(code);
  }
  if (exponent10 < 0) return new Error(undefined);
  let val = BigInt(str) * (10n ** BigInt(exponent10));
  if (negative) val = -val;
  if (val < -9007199254740991n || val > 9007199254740991n) {
    return new Error(undefined);
  }
  return new Ok(Number(val));
}
