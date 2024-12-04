import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json/blueprint

pub fn main() {
  gleeunit.main()
}

type Tree {
  Node(value: Int, left: Option(Tree), right: Option(Tree))
}

type ListOfTrees(t) {
  ListOfTrees(head: t, tail: ListOfTrees(t))
  NoTrees
}

fn encode_tree(tree: Tree) -> json.Json {
  blueprint.union_type_encoder(tree, fn(node) {
    case node {
      Node(value, left, right) -> #(
        "node",
        [
          #("value", json.int(value)),
          #("right", json.nullable(right, encode_tree)),
        ]
          |> blueprint.encode_optional_field("left", left, encode_tree)
          |> json.object(),
      )
    }
  })
}

fn encode_list_of_trees(tree: ListOfTrees(Tree)) -> json.Json {
  blueprint.union_type_encoder(tree, fn(list) {
    case list {
      ListOfTrees(head, tail) -> #(
        "list",
        json.object([
          #("head", encode_tree(head)),
          #("tail", encode_list_of_trees(tail)),
        ]),
      )
      NoTrees -> #("no_trees", json.object([]))
    }
  })
}

// Without reuse_decoder, recursive types would cause infinite schema expansion
fn tree_decoder() {
  blueprint.union_type_decoder([
    #(
      "node",
      blueprint.decode3(
        Node,
        blueprint.field("value", blueprint.int()),
        // testing both an optional field a field with a possible null
        blueprint.optional_field("left", blueprint.self_decoder(tree_decoder)),
        blueprint.field(
          "right",
          blueprint.optional(blueprint.self_decoder(tree_decoder)),
        ),
      ),
    ),
  ])
  // !!!IMPORTANT!!! Add the reuse_decoder when there are nested recursive types so
  // the schema references (`#`) get rewritten correctly and self-references from the
  // different types don't get mixed up. As a recommendation, always add it when
  // decoding recursive types.
  |> blueprint.reuse_decoder
}

fn decode_list_of_trees() {
  blueprint.union_type_decoder([
    #(
      "list",
      blueprint.decode2(
        ListOfTrees,
        blueprint.field("head", tree_decoder()),
        blueprint.field("tail", blueprint.self_decoder(decode_list_of_trees)),
      ),
    ),
    #("no_trees", blueprint.decode0(NoTrees)),
  ])
}

pub fn tree_decoder_test() {
  // Create a sample tree structure:
  //       5
  //      / \
  //     3   7
  //    /     \
  //   1       9
  let tree =
    Node(
      value: 5,
      left: Some(Node(value: 3, left: Some(Node(1, None, None)), right: None)),
      right: Some(Node(value: 7, left: None, right: Some(Node(9, None, None)))),
    )

  // Create a list of trees
  let tree_list =
    ListOfTrees(
      Node(value: 1, left: None, right: None),
      ListOfTrees(
        Node(
          value: 10,
          left: Some(Node(value: 1, left: None, right: None)),
          right: None,
        ),
        NoTrees,
      ),
    )

  // Test encoding
  let json_str = tree |> encode_tree |> json.to_string()
  let list_json_str = tree_list |> encode_list_of_trees |> json.to_string()

  // Test decoding
  let decoded = blueprint.decode(using: tree_decoder(), from: json_str)

  decoded
  |> should.equal(Ok(tree))

  let decoded_list =
    blueprint.decode(using: decode_list_of_trees(), from: list_json_str)

  decoded_list
  |> should.equal(Ok(tree_list))

  // Test schema generation
  blueprint.generate_json_schema(decode_list_of_trees())
  |> json.to_string
  |> io.println
}

pub fn tree_decoder_match_str_test() {
  let tree =
    Node(
      value: 5,
      left: Some(Node(value: 3, left: Some(Node(1, None, None)), right: None)),
      right: Some(Node(value: 7, left: None, right: Some(Node(9, None, None)))),
    )

  // Create a list of trees
  let tree_list =
    ListOfTrees(
      Node(value: 1, left: None, right: None),
      ListOfTrees(
        Node(
          value: 10,
          left: Some(Node(value: 1, left: None, right: None)),
          right: None,
        ),
        NoTrees,
      ),
    )

  // Test encoding
  let json_str = tree |> encode_tree |> json.to_string()
  let list_json_str = tree_list |> encode_list_of_trees |> json.to_string()

  // Test specific JSON structure
  json_str
  |> should.equal(
    "{\"type\":\"node\",\"data\":{\"left\":{\"type\":\"node\",\"data\":{\"left\":{\"type\":\"node\",\"data\":{\"value\":1,\"right\":null}},\"value\":3,\"right\":null}},\"value\":5,\"right\":{\"type\":\"node\",\"data\":{\"value\":7,\"right\":{\"type\":\"node\",\"data\":{\"value\":9,\"right\":null}}}}}}",
  )

  list_json_str
  |> should.equal(
    "{\"type\":\"list\",\"data\":{\"head\":{\"type\":\"node\",\"data\":{\"value\":1,\"right\":null}},\"tail\":{\"type\":\"list\",\"data\":{\"head\":{\"type\":\"node\",\"data\":{\"left\":{\"type\":\"node\",\"data\":{\"value\":1,\"right\":null}},\"value\":10,\"right\":null}},\"tail\":{\"type\":\"no_trees\",\"data\":{}}}}}}",
  )

  // Test schema generation
  let schema = blueprint.generate_json_schema(decode_list_of_trees())

  schema
  |> json.to_string
  |> should.equal(
    "{\"$defs\":{\"ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2\":{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"node\"]},\"data\":{\"required\":[\"value\",\"right\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\"},\"left\":{\"$ref\":\"#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2\"},\"right\":{\"anyOf\":[{\"$ref\":\"#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2\"},{\"type\":\"null\"}]}}}}}},\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"anyOf\":[{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"list\"]},\"data\":{\"required\":[\"head\",\"tail\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"head\":{\"$ref\":\"#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2\"},\"tail\":{\"$ref\":\"#\"}}}}},{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"no_trees\"]},\"data\":{\"additionalProperties\":false,\"type\":\"object\",\"properties\":{}}}}]}",
  )
}
