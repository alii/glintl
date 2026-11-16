//// Reads settings from a tag's Unicode extension the same way Intl does. In
//// `"ja-JP-u-ca-japanese"`, that's the Japanese calendar.

import gleam/list
import gleam/string
import glintl.{type Locale}

/// Splits a lowercase tag into its base and its `u` keywords, so
/// `"ja-jp-u-ca-japanese"` gives `#("ja-jp", [#("ca", "japanese")])`.
pub fn split(tag: String) -> #(String, List(#(String, String))) {
  let subtags = string.split(tag, "-")
  let base = list.take_while(subtags, fn(subtag) { !is_singleton(subtag) })
  #(string.join(base, "-"), keywords(u_extension(subtags)))
}

/// Like Intl, unknown values are ignored.
pub fn apply(locale: Locale, keywords: List(#(String, String))) -> Locale {
  list.fold(keywords, locale, fn(locale, keyword) {
    case keyword {
      #("ca", name) ->
        case glintl.calendar_from_name(name) {
          Ok(calendar) -> glintl.with_calendar(locale, calendar)
          Error(Nil) -> locale
        }
      #("hc", name) ->
        case hour_cycle(name) {
          Ok(hour_cycle) -> glintl.with_hour_cycle(locale, hour_cycle)
          Error(Nil) -> locale
        }
      #("nu", name) ->
        case glintl.numbering_system(name) {
          Ok(numbering_system) ->
            glintl.with_numbering_system(locale, numbering_system)
          Error(Nil) -> locale
        }
      _ -> locale
    }
  })
}

/// A single letter starts an extension or private use.
fn is_singleton(subtag: String) -> Bool {
  string.length(subtag) == 1
}

/// Everything after `x` is private use, so it's ignored.
fn u_extension(subtags: List(String)) -> List(String) {
  case subtags {
    [] | ["x", ..] -> []
    ["u", ..rest] -> list.take_while(rest, fn(s) { !is_singleton(s) })
    [_, ..rest] -> u_extension(rest)
  }
}

/// Attributes come before the first key. Like Intl, the first value for a key
/// wins.
fn keywords(subtags: List(String)) -> List(#(String, String)) {
  case subtags {
    [] -> []
    [key, ..rest] ->
      case string.length(key) {
        2 -> {
          let value = list.take_while(rest, fn(s) { string.length(s) > 2 })
          let rest = list.drop(rest, list.length(value))
          let others =
            keywords(rest) |> list.filter(fn(keyword) { keyword.0 != key })
          [#(key, string.join(value, "-")), ..others]
        }
        _ -> keywords(rest)
      }
  }
}

fn hour_cycle(name: String) -> Result(glintl.HourCycle, Nil) {
  case name {
    "h11" -> Ok(glintl.H11)
    "h12" -> Ok(glintl.H12)
    "h23" -> Ok(glintl.H23)
    "h24" -> Ok(glintl.H24)
    _ -> Error(Nil)
  }
}
