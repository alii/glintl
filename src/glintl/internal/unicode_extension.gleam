//// Reads the settings in a tag's Unicode extension, like the calendar in
//// `"ja-JP-u-ca-japanese"`, the way Intl does.

import gleam/list
import gleam/string
import glintl.{type Locale}

/// Splits a lowercase tag into the part before its extensions and its `u`
/// extension's keywords, like `#("ja-jp", [#("ca", "japanese")])`.
pub fn split(tag: String) -> #(String, List(#(String, String))) {
  let subtags = string.split(tag, "-")
  let base = list.take_while(subtags, fn(subtag) { !is_singleton(subtag) })
  #(string.join(base, "-"), keywords(u_extension(subtags)))
}

/// Sets what the keywords ask for. Like Intl, it ignores values it doesn't
/// know.
pub fn apply(locale: Locale, keywords: List(#(String, String))) -> Locale {
  list.fold(keywords, locale, fn(locale, keyword) {
    case keyword {
      #("ca", name) ->
        case calendar(name) {
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

/// One letter starts an extension, like `u`, or private use, `x`.
fn is_singleton(subtag: String) -> Bool {
  string.length(subtag) == 1
}

/// The subtags of the `u` extension. Everything after `x` is private use.
fn u_extension(subtags: List(String)) -> List(String) {
  case subtags {
    [] | ["x", ..] -> []
    ["u", ..rest] -> list.take_while(rest, fn(s) { !is_singleton(s) })
    [_, ..rest] -> u_extension(rest)
  }
}

/// Each two letter key with its value, like `#("ca", "islamic-civil")`.
/// Attributes come before the first key, and the first of each key counts.
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

/// A calendar by its Unicode name, with the aliases Intl takes.
fn calendar(name: String) -> Result(glintl.Calendar, Nil) {
  case name {
    "gregory" -> Ok(glintl.Gregorian)
    "iso8601" -> Ok(glintl.Iso8601)
    "buddhist" -> Ok(glintl.Buddhist)
    "japanese" -> Ok(glintl.Japanese)
    "roc" -> Ok(glintl.RepublicOfChina)
    "persian" -> Ok(glintl.Persian)
    "indian" -> Ok(glintl.Indian)
    "hebrew" -> Ok(glintl.Hebrew)
    "chinese" -> Ok(glintl.Chinese)
    "dangi" -> Ok(glintl.Dangi)
    "coptic" -> Ok(glintl.Coptic)
    "ethiopic" -> Ok(glintl.Ethiopic)
    "ethioaa" | "ethiopic-amete-alem" -> Ok(glintl.EthiopicAmeteAlem)
    "islamic-civil" | "islamicc" -> Ok(glintl.IslamicCivil)
    "islamic-tbla" | "islamic" -> Ok(glintl.IslamicTabular)
    "islamic-umalqura" -> Ok(glintl.IslamicUmmAlQura)
    // ICU has no Saudi sighting calendar, so it uses Gregorian.
    "islamic-rgsa" -> Ok(glintl.Gregorian)
    _ -> Error(Nil)
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
