export function map_with_undefined() {
  return new Map([["present", undefined]]);
}

export function weak_map_pair() {
  const key = {};
  return [new WeakMap([[key, undefined]]), key];
}

export function null_proto_object() {
  const object = Object.create(null);
  object.present = undefined;
  return object;
}
