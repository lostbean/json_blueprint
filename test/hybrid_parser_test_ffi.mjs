import * as codec from "./json/blueprint/codec.mjs";
import { Ok } from "./gleam.mjs";
import { Option$None$const as none } from "../gleam_stdlib/gleam/option.mjs";

export function callback_range_error_escapes() {
  const failure = new RangeError("application callback");
  const custom = codec.custom(
    (raw) => new Ok(raw),
    () => {
      throw failure;
    },
    none,
    undefined,
  );
  try {
    codec.decode_json(custom, "null");
    return false;
  } catch (error) {
    return error === failure;
  }
}
