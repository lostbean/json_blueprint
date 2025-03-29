// Subset copied from the original and now deprecated decoder in gleam/dynamic in gleam_stdlib
// Migration to the new decoder is difficult at moment
// https://github.com/gleam-lang/stdlib/blob/v0.58.0/src/gleam_stdlib.mjs

import {
  BitArray,
  Error,
  List,
  Ok,
  Result,
  NonEmpty,
} from "../gleam_stdlib/gleam.mjs";
import { DecodeError } from "../gleam_stdlib/gleam/dynamic.mjs";
import { Some, None } from "../gleam_stdlib/gleam/option.mjs";
import Dict from "../gleam_stdlib/dict.mjs";

const Nil = undefined;

export function identity(x) {
  return x;
}

export function length(data) {
  return data.length;
}

export function classify_dynamic(data) {
  if (typeof data === "string") {
    return "String";
  } else if (typeof data === "boolean") {
    return "Bool";
  } else if (data instanceof Result) {
    return "Result";
  } else if (data instanceof List) {
    return "List";
  } else if (data instanceof BitArray) {
    return "BitArray";
  } else if (data instanceof Dict) {
    return "Dict";
  } else if (Number.isInteger(data)) {
    return "Int";
  } else if (Array.isArray(data)) {
    return `Tuple of ${data.length} elements`;
  } else if (typeof data === "number") {
    return "Float";
  } else if (data === null) {
    return "Null";
  } else if (data === undefined) {
    return "Nil";
  } else {
    const type = typeof data;
    return type.charAt(0).toUpperCase() + type.slice(1);
  }
}

function decoder_error(expected, got) {
  return decoder_error_no_classify(expected, classify_dynamic(got));
}

function decoder_error_no_classify(expected, got) {
  return new Error(
    List.fromArray([new DecodeError(expected, got, List.fromArray([]))]),
  );
}

export function decode_string(data) {
  return typeof data === "string"
    ? new Ok(data)
    : decoder_error("String", data);
}

export function decode_int(data) {
  return Number.isInteger(data) ? new Ok(data) : decoder_error("Int", data);
}

export function decode_float(data) {
  return typeof data === "number" ? new Ok(data) : decoder_error("Float", data);
}

export function decode_bool(data) {
  return typeof data === "boolean" ? new Ok(data) : decoder_error("Bool", data);
}

export function decode_bit_array(data) {
  if (data instanceof BitArray) {
    return new Ok(data);
  }
  if (data instanceof Uint8Array) {
    return new Ok(new BitArray(data));
  }
  return decoder_error("BitArray", data);
}

export function decode_tuple(data) {
  return Array.isArray(data) ? new Ok(data) : decoder_error("Tuple", data);
}

export function decode_tuple2(data) {
  return decode_tupleN(data, 2);
}

export function decode_tuple3(data) {
  return decode_tupleN(data, 3);
}

export function decode_tuple4(data) {
  return decode_tupleN(data, 4);
}

export function decode_tuple5(data) {
  return decode_tupleN(data, 5);
}

export function decode_tuple6(data) {
  return decode_tupleN(data, 6);
}

function decode_tupleN(data, n) {
  if (Array.isArray(data) && data.length == n) {
    return new Ok(data);
  }

  const list = decode_exact_length_list(data, n);
  if (list) return new Ok(list);

  return decoder_error(`Tuple of ${n} elements`, data);
}

function decode_exact_length_list(data, n) {
  if (!(data instanceof List)) return;

  const elements = [];
  let current = data;

  for (let i = 0; i < n; i++) {
    if (!(current instanceof NonEmpty)) break;
    elements.push(current.head);
    current = current.tail;
  }

  if (elements.length === n && !(current instanceof NonEmpty)) return elements;
}

export function tuple_get(data, index) {
  return index >= 0 && data.length > index
    ? new Ok(data[index])
    : new Error(Nil);
}

export function decode_list(data) {
  if (Array.isArray(data)) {
    return new Ok(List.fromArray(data));
  }
  return data instanceof List ? new Ok(data) : decoder_error("List", data);
}

export function decode_result(data) {
  return data instanceof Result ? new Ok(data) : decoder_error("Result", data);
}

export function decode_map(data) {
  if (data instanceof Dict) {
    return new Ok(data);
  }
  if (data instanceof Map || data instanceof WeakMap) {
    return new Ok(Dict.fromMap(data));
  }
  if (data == null) {
    return decoder_error("Dict", data);
  }
  if (typeof data !== "object") {
    return decoder_error("Dict", data);
  }
  const proto = Object.getPrototypeOf(data);
  if (proto === Object.prototype || proto === null) {
    return new Ok(Dict.fromObject(data));
  }
  return decoder_error("Dict", data);
}

export function decode_option(data, decoder) {
  if (data === null || data === undefined || data instanceof None)
    return new Ok(new None());
  if (data instanceof Some) data = data[0];
  const result = decoder(data);
  if (result.isOk()) {
    return new Ok(new Some(result[0]));
  } else {
    return result;
  }
}

export function decode_field(value, name) {
  const not_a_map_error = () => decoder_error("Dict", value);

  if (
    value instanceof Dict ||
    value instanceof WeakMap ||
    value instanceof Map
  ) {
    const entry = map_get(value, name);
    return new Ok(entry.isOk() ? new Some(entry[0]) : new None());
  } else if (value === null) {
    return not_a_map_error();
  } else if (Object.getPrototypeOf(value) == Object.prototype) {
    return try_get_field(value, name, () => new Ok(new None()));
  } else {
    return try_get_field(value, name, not_a_map_error);
  }
}

function try_get_field(value, field, or_else) {
  try {
    return field in value ? new Ok(new Some(value[field])) : or_else();
  } catch {
    return or_else();
  }
}
