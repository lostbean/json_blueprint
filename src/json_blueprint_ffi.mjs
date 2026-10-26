import { Ok, Error } from "./gleam.mjs";

export function do_null() {
  return null;
}

// TextEncoder replaces raw lone surrogates. Refuse them while the original
// UTF-16 code units are still available; valid pairs consume both units.
export function validate_scalars(source) {
  for (let i = 0; i < source.length; i++) {
    const unit = source.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = source.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        i++;
      } else {
        return new Error(undefined);
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return new Error(undefined);
    }
  }
  return new Ok(undefined);
}

// Each UTF-16 code unit encodes to between one and three UTF-8 bytes (a
// surrogate pair is two units and four bytes), so most inputs are decided by
// their length alone and none is copied.
export function utf8_byte_size_exceeds(string, max) {
  const units = string.length;
  if (units > max) return true;
  if (units * 3 <= max) return false;
  let bytes = 0;
  for (let i = 0; i < units; i++) {
    const unit = string.charCodeAt(i);
    if (unit < 0x80) {
      bytes += 1;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < units) {
      const next = string.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
    if (bytes > max) return true;
  }
  return false;
}

// Convert host stack/capacity exhaustion into the parser's explicit outcome.
// Application errors and implementation defects must not become JSON failures.
export function with_parser_capacity(work, capacityError) {
  try {
    return work();
  } catch (error) {
    if (error instanceof RangeError) return new Error(capacityError);
    throw error;
  }
}
