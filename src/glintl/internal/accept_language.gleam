//// Reads an `Accept-Language` header, like `"fr-CH, fr;q=0.9, en;q=0.8"`.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// The highest weight, given to tags without a `q`.
const highest = 1.0

/// The header's language tags, most wanted first. Tags with a weight of 0,
/// a weight that isn't a number, or `*` are left out.
pub fn tags(header: String) -> List(String) {
  header
  |> string.split(",")
  |> list.filter_map(weighted)
  |> list.sort(fn(a, b) { float.compare(b.1, a.1) })
  |> list.map(fn(pair) { pair.0 })
}

fn weighted(item: String) -> Result(#(String, Float), Nil) {
  let #(tag, parameters) = case string.split(item, ";") {
    [tag, ..parameters] -> #(string.trim(tag), parameters)
    [] -> #("", [])
  }
  case tag, weight(parameters) {
    "", _ | "*", _ -> Error(Nil)
    _, Ok(q) if q >. 0.0 -> Ok(#(tag, q))
    _, _ -> Error(Nil)
  }
}

/// The `q` parameter, or the highest weight if there isn't one.
fn weight(parameters: List(String)) -> Result(Float, Nil) {
  case parameters {
    [] -> Ok(highest)
    [parameter, ..rest] ->
      case string.trim(parameter) |> string.lowercase {
        "q=" <> q -> number(q)
        _ -> weight(rest)
      }
  }
}

fn number(text: String) -> Result(Float, Nil) {
  case float.parse(text), int.parse(text) {
    Ok(n), _ -> Ok(n)
    _, Ok(n) -> Ok(int.to_float(n))
    _, _ -> Error(Nil)
  }
}
