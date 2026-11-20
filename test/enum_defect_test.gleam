//// Repeated enum labels and values are reported the same way for a few
//// labels and for many.

import gleam/int
import gleam/list
import gleeunit/should
import json/blueprint/codec

fn labels(count: Int) -> List(#(String, Int)) {
  int.range(0, count, [], fn(done, i) {
    [#("l" <> int.to_string(i), i), ..done]
  })
  |> list.reverse
}

fn first_mistake(
  variants: List(#(String, Int)),
) -> Result(Nil, codec.DefinitionError) {
  codec.string_enum(variants) |> codec.check |> result_nil
}

fn result_nil(outcome: Result(a, e)) -> Result(Nil, e) {
  case outcome {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}

pub fn a_repeated_label_is_reported_for_few_and_many_labels_test() {
  [3, 30]
  |> list.each(fn(count) {
    first_mistake(list.append(labels(count), [#("l1", 999)]))
    |> should.equal(Error(codec.DuplicateEnumLabel("l1")))
  })
}

pub fn a_repeated_value_is_reported_for_few_and_many_labels_test() {
  [3, 30]
  |> list.each(fn(count) {
    first_mistake(list.append(labels(count), [#("again", 2)]))
    |> should.equal(Error(codec.DuplicateEnumValue("again")))
  })
}

pub fn the_first_mistake_wins_for_few_and_many_labels_test() {
  [3, 30]
  |> list.each(fn(count) {
    first_mistake(list.append(labels(count), [#("twice", 1), #("l0", 500)]))
    |> should.equal(Error(codec.DuplicateEnumValue("twice")))
  })
}
