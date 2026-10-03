//// The representation behind the opaque `codec.Schema`. Only this package
//// and the modules that `json_blueprint_codegen` generates use it; callers
//// read a schema through `codec.view` and `codec.description`, so this type
//// can gain variants without breaking them. Generated modules construct it
//// in `const` declarations, so its existing constructors stay as they are
//// within a major version.

import gleam/option.{type Option}
import json/blueprint/number.{type Number}

/// A schema node, within the finite Draft 2020-12 profile that codecs
/// describe. Generated modules build it in `const` declarations.
pub type Tree {
  DescribedSchema(description: String, inner: Tree)
  StringSchema
  StringEnumSchema(labels: List(String))
  IntSchema
  NumberSchema
  BoolSchema
  PairSchema(left: Tree, right: Tree)
  ListSchema(items: Tree)
  NullableSchema(inner: Tree)
  ObjectSchema(properties: List(PropertySchema))
  UnionSchema(variants: List(VariantSchema))
  IntegerRangeSchema(minimum: Int, maximum: Int)
  NumberRangeSchema(minimum: Number, maximum: Number)
  /// Any JSON value: `{}` in a document.
  AnySchema
}

/// One property of an `ObjectSchema`.
pub type PropertySchema {
  PropertySchema(name: String, required: Bool, schema: Tree)
}

/// One variant of a `UnionSchema`. A unit variant has no payload.
pub type VariantSchema {
  VariantSchema(tag: String, payload: Option(Tree))
}
