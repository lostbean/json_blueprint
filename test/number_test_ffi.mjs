export function float_from_hex(hex) {
  const buf = new ArrayBuffer(8);
  const view = new DataView(buf);
  const hi = parseInt(hex.slice(0, 8), 16);
  const lo = parseInt(hex.slice(8, 16), 16);
  view.setUint32(0, hi);
  view.setUint32(4, lo);
  return view.getFloat64(0);
}

export function float_to_bits_hex(value) {
  const buf = new ArrayBuffer(8);
  const view = new DataView(buf);
  view.setFloat64(0, value);
  const hi = view.getUint32(0).toString(16).padStart(8, "0");
  const lo = view.getUint32(4).toString(16).padStart(8, "0");
  return hi + lo;
}

export function call_from_int_raw(fn_from_int, kind) {
  switch (kind) {
    case "nan":
      return fn_from_int(NaN);
    case "infinity":
      return fn_from_int(Infinity);
    case "neg_infinity":
      return fn_from_int(-Infinity);
    case "fractional":
      return fn_from_int(1.5);
    case "unsafe_int":
      return fn_from_int(9007199254740992);
    case "rounded_before_construction":
      // In JS, 9007199254740993 is rounded to 9007199254740992 before construction
      return fn_from_int(9007199254740993);
    case "neg_unsafe_int":
      return fn_from_int(-9007199254740992);
    case "max_safe":
      return fn_from_int(9007199254740991);
    case "min_safe":
      return fn_from_int(-9007199254740991);
    default:
      throw new Error("Unknown kind: " + kind);
  }
}
