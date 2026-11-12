//// This module copies ICU's DateTimePatternGenerator, which picks a pattern
//// for some fields. It also copies the way JavaScriptCore calls it.
//// `codegen/matcher.ts` does the same, and the generator checks both against
//// Intl. The JavaScript target uses only `Request`.

@target(erlang)
import gleam/bit_array
@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
@target(erlang)
import gleam/string

/// The fields to show, as `Intl.DateTimeFormat` options like `"short"` or
/// `"2-digit"`. A field that isn't shown is `""`, and no fraction is 0.
pub type Request {
  Request(
    weekday: String,
    era: String,
    year: String,
    month: String,
    day: String,
    day_period: String,
    hour: String,
    minute: String,
    second: String,
    fractional_second_digits: Int,
    time_zone_name: String,
    /// `"h11"` to `"h24"`, or `""` for the locale's own.
    hour_cycle: String,
  )
}

// --- Fields ------------------------------------------------------------------

@target(erlang)
const era = 0

@target(erlang)
const year = 1

@target(erlang)
const month = 3

@target(erlang)
const weekday = 6

@target(erlang)
const day_period = 10

@target(erlang)
const hour = 11

@target(erlang)
const minute = 12

@target(erlang)
const second = 13

@target(erlang)
const fractional_second = 14

@target(erlang)
const zone = 15

@target(erlang)
/// What each kind of difference between fields costs, from ICU's
/// `dtptngen_impl.h`.
const none = 0

@target(erlang)
const extra_field = 0x10000

@target(erlang)
const missing_field = 0x1000

@target(erlang)
const narrow = -0x101

@target(erlang)
const shorter = -0x102

@target(erlang)
const short = -0x103

@target(erlang)
const long = -0x104

@target(erlang)
const numeric = 0x100

@target(erlang)
const delta = 0x10

@target(erlang)
const fix_fractional_seconds = 1

@target(erlang)
/// Masks of fields, with one bit for each field.
const all_fields = -1

@target(erlang)
const date_mask = 0x3ff

@target(erlang)
const time_mask = 0xfc00

@target(erlang)
const fractional_mask = 0x4000

@target(erlang)
const second_and_fractional_mask = 0x6000

@target(erlang)
/// A pattern letter's field and how it compares, from ICU's `dtTypes`.
type Row {
  Row(field: Int, kind: Int, min_length: Int)
}

@target(erlang)
/// Each letter's rows, from the shortest.
fn rows(letter: String) -> List(Row) {
  case letter {
    "G" -> [Row(era, short, 1), Row(era, long, 4), Row(era, narrow, 5)]
    "y" -> [Row(year, numeric, 1)]
    "Y" -> [Row(year, numeric + delta, 1)]
    "u" -> [Row(year, numeric + 2 * delta, 1)]
    "r" -> [Row(year, numeric + 3 * delta, 1)]
    "U" -> [Row(year, short, 1), Row(year, long, 4), Row(year, narrow, 5)]
    "Q" -> [
      Row(2, numeric, 1),
      Row(2, short, 3),
      Row(2, long, 4),
      Row(2, narrow, 5),
    ]
    "q" -> [
      Row(2, numeric + delta, 1),
      Row(2, short - delta, 3),
      Row(2, long - delta, 4),
      Row(2, narrow - delta, 5),
    ]
    "M" -> [
      Row(month, numeric, 1),
      Row(month, short, 3),
      Row(month, long, 4),
      Row(month, narrow, 5),
    ]
    "L" -> [
      Row(month, numeric + delta, 1),
      Row(month, short - delta, 3),
      Row(month, long - delta, 4),
      Row(month, narrow - delta, 5),
    ]
    "l" -> [Row(month, numeric + delta, 1)]
    "w" -> [Row(4, numeric, 1)]
    "W" -> [Row(5, numeric, 1)]
    "E" -> [
      Row(weekday, short, 1),
      Row(weekday, long, 4),
      Row(weekday, narrow, 5),
      Row(weekday, shorter, 6),
    ]
    "c" -> [
      Row(weekday, numeric + 2 * delta, 1),
      Row(weekday, short - 2 * delta, 3),
      Row(weekday, long - 2 * delta, 4),
      Row(weekday, narrow - 2 * delta, 5),
      Row(weekday, shorter - 2 * delta, 6),
    ]
    "e" -> [
      Row(weekday, numeric + delta, 1),
      Row(weekday, short - delta, 3),
      Row(weekday, long - delta, 4),
      Row(weekday, narrow - delta, 5),
      Row(weekday, shorter - delta, 6),
    ]
    "d" -> [Row(9, numeric, 1), Row(9, short, 3)]
    "g" -> [Row(9, numeric + delta, 1)]
    "D" -> [Row(7, numeric, 1)]
    "F" -> [Row(8, numeric, 1)]
    "a" -> [
      Row(day_period, short, 1),
      Row(day_period, long, 4),
      Row(day_period, narrow, 5),
    ]
    "b" -> [
      Row(day_period, short - delta, 1),
      Row(day_period, long - delta, 4),
      Row(day_period, narrow - delta, 5),
    ]
    "B" -> [
      Row(day_period, short - 3 * delta, 1),
      Row(day_period, long - 3 * delta, 4),
      Row(day_period, narrow - 3 * delta, 5),
    ]
    "H" -> [Row(hour, numeric + 10 * delta, 1)]
    "k" -> [Row(hour, numeric + 11 * delta, 1)]
    "h" -> [Row(hour, numeric, 1)]
    "K" -> [Row(hour, numeric + delta, 1)]
    "J" -> [Row(hour, numeric + 5 * delta, 1)]
    "j" -> [Row(hour, numeric + 6 * delta, 1)]
    "C" -> [Row(hour, numeric + 7 * delta, 1)]
    "m" -> [Row(minute, numeric, 1)]
    "s" -> [Row(second, numeric, 1)]
    "A" -> [Row(second, numeric + delta, 1)]
    "S" -> [Row(fractional_second, numeric, 1)]
    "v" -> [Row(zone, short - 2 * delta, 1), Row(zone, long - 2 * delta, 4)]
    "z" -> [Row(zone, short, 1), Row(zone, long, 4)]
    "Z" -> [
      Row(zone, narrow - delta, 1),
      Row(zone, long - delta, 4),
      Row(zone, short - delta, 5),
    ]
    "O" -> [Row(zone, short - delta, 1), Row(zone, long - delta, 4)]
    "V" -> [
      Row(zone, short - delta, 1),
      Row(zone, long - delta, 2),
      Row(zone, long - 1 - delta, 3),
      Row(zone, long - 2 - delta, 4),
    ]
    "X" | "x" -> [
      Row(zone, narrow - delta, 1),
      Row(zone, short - delta, 2),
      Row(zone, long - delta, 4),
    ]
    _ -> []
  }
}

@target(erlang)
/// A pattern letter's field, like `era` or `month`.
pub fn field_of(letter: String) -> Result(Int, Nil) {
  case rows(letter) {
    [Row(field:, ..), ..] -> Ok(field)
    [] -> Error(Nil)
  }
}

@target(erlang)
/// Like ICU's `getCanonicalIndex`: finds the longest row a run is long enough
/// for.
fn row(run: String) -> Result(Row, Nil) {
  // Pattern letters are ASCII, so a run's length is its byte size.
  case <<run:utf8>> {
    <<c, rest:bits>> if c < ascii_end ->
      case same_bytes(rest, c, 1) == string.byte_size(run) {
        True -> longest(rows(ascii(c)), string.byte_size(run))
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

@target(erlang)
/// Bytes from here up are part of a character that takes more than one byte.
const ascii_end = 0x80

@target(erlang)
fn ascii(c: Int) -> String {
  let assert Ok(text) = bit_array.to_string(<<c>>)
  text
}

@target(erlang)
/// Counts how many bytes at the start are `c`, and adds `n`.
fn same_bytes(bits: BitArray, c: Int, n: Int) -> Int {
  case bits {
    <<d, rest:bits>> if d == c -> same_bytes(rest, c, n + 1)
    _ -> n
  }
}

@target(erlang)
fn longest(rows: List(Row), length: Int) -> Result(Row, Nil) {
  case rows {
    [_, next, ..rest] if next.min_length <= length ->
      longest([next, ..rest], length)
    [first, ..] -> Ok(first)
    [] -> Error(Nil)
  }
}

// --- Patterns ----------------------------------------------------------------

@target(erlang)
const quote = "'"

@target(erlang)
/// ICU's `FormatParser` keeps only this many items of a pattern.
const max_items = 50

@target(erlang)
/// Splits a pattern into runs of one letter and single other characters.
fn items(pattern: String) -> List(String) {
  let all = case ascii_runs(<<pattern:utf8>>, []) {
    Ok(all) -> all
    Error(Nil) -> runs(characters(pattern), [])
  }
  list.take(all, max_items)
}

@target(erlang)
/// Like `runs`, but faster. It works only on ASCII text, like skeletons.
fn ascii_runs(bits: BitArray, out: List(String)) -> Result(List(String), Nil) {
  case bits {
    <<c, _:bits>> if c < ascii_end -> {
      let n = case is_letter(ascii(c)) {
        True -> same_bytes(bits, c, 0)
        False -> 1
      }
      let assert <<run:bytes-size(n), rest:bits>> = bits
      let assert Ok(text) = bit_array.to_string(run)
      ascii_runs(rest, [text, ..out])
    }
    <<>> -> Ok(list.reverse(out))
    _ -> Error(Nil)
  }
}

@target(erlang)
fn runs(chars: List(String), out: List(String)) -> List(String) {
  case chars, out {
    [], _ -> list.reverse(out)
    [c, ..rest], [last, ..done] ->
      case is_letter(c) && string.starts_with(last, c) {
        True -> runs(rest, [last <> c, ..done])
        False -> runs(rest, [c, ..out])
      }
    [c, ..rest], [] -> runs(rest, [c])
  }
}

@target(erlang)
fn is_letter(c: String) -> Bool {
  case c {
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M" -> True
    "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m" -> True
    "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

@target(erlang)
/// Like ICU's `getQuoteLiteral`: joins a quoted run, quotes and all, from a
/// list starting at its opening quote. Returns it and the items after it.
fn quote_literal(list: List(String)) -> #(String, List(String)) {
  case list {
    [first, ..rest] -> quoted(rest, first)
    [] -> #("", [])
  }
}

@target(erlang)
fn quoted(list: List(String), text: String) -> #(String, List(String)) {
  case list {
    [] -> #(text, [])
    ["'", "'", ..rest] -> quoted(rest, text <> "''")
    ["'", ..rest] -> #(text <> "'", rest)
    [item, ..rest] -> quoted(rest, text <> item)
  }
}

@target(erlang)
/// Whether a field is only separators. Like ICU, it looks for a dot in the
/// item at each character's index, not in the character itself.
fn is_separator(field: String, all: List(String)) -> Bool {
  field
  |> characters
  |> list.index_fold(True, fn(ok, c, i) {
    ok
    && {
      string.contains("'\\ :\",-", c)
      || case list.drop(all, i) {
        [item, ..] -> string.starts_with(item, ".")
        [] -> False
      }
    }
  })
}

// --- Skeletons ---------------------------------------------------------------

@target(erlang)
/// A field in a skeleton. `kind` and `base_length` come from the letter's
/// row.
type Field {
  Field(field: Int, letter: String, length: Int, kind: Int, base_length: Int)
}

@target(erlang)
/// The fields a skeleton has, by field number.
type Skeleton =
  List(Field)

@target(erlang)
fn put(skeleton: Skeleton, new: Field) -> Skeleton {
  case skeleton {
    [] -> [new]
    [first, ..rest] if first.field < new.field -> [first, ..put(rest, new)]
    [first, ..rest] if first.field == new.field -> [new, ..rest]
    _ -> [new, ..skeleton]
  }
}

@target(erlang)
fn drop(skeleton: Skeleton, field: Int) -> Skeleton {
  list.filter(skeleton, fn(f) { f.field != field })
}

@target(erlang)
fn get(skeleton: Skeleton, field: Int) -> Result(Field, Nil) {
  list.find(skeleton, fn(f) { f.field == field })
}

@target(erlang)
fn length(skeleton: Skeleton, field: Int) -> Int {
  case get(skeleton, field) {
    Ok(f) -> f.length
    Error(Nil) -> 0
  }
}

@target(erlang)
/// Like ICU's `DateTimeMatcher::set`.
fn skeleton(pattern: String) -> Skeleton {
  let parsed = parse(items(pattern), [])
  let has = fn(s, field) { result_is_ok(get(s, field)) }
  // ICU-20739: minutes and fractions of a second need seconds.
  let parsed = case
    has(parsed, minute)
    && has(parsed, fractional_second)
    && !has(parsed, second)
  {
    True -> put(parsed, Field(second, "s", 1, numeric + 1, 1))
    False -> parsed
  }
  // ICU-13183: a 12 hour clock needs a day period, and others have none.
  case get(parsed, hour) {
    Ok(Field(letter: "h", ..)) | Ok(Field(letter: "K", ..)) ->
      case has(parsed, day_period) {
        True -> parsed
        False -> put(parsed, Field(day_period, "a", 1, short, 1))
      }
    Ok(_) -> drop(parsed, day_period)
    Error(Nil) -> parsed
  }
}

@target(erlang)
fn result_is_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

@target(erlang)
fn parse(items: List(String), skeleton: Skeleton) -> Skeleton {
  case items {
    [] -> skeleton
    ["'", ..] -> {
      let #(_, rest) = quote_literal(items)
      parse(rest, skeleton)
    }
    [item, ..rest] ->
      case row(item) {
        Ok(r) -> {
          let length = string.byte_size(item)
          let kind = case r.kind > 0 {
            True -> r.kind + length
            False -> r.kind
          }
          let assert Ok(letter) = string.first(item)
          parse(
            rest,
            put(skeleton, Field(r.field, letter, length, kind, r.min_length)),
          )
        }
        Error(Nil) -> parse(rest, skeleton)
      }
  }
}

@target(erlang)
type Distance {
  Distance(distance: Int, missing: Int, extra: Int)
}

@target(erlang)
fn distance(want: Skeleton, other: Skeleton, mask: Int) -> Distance {
  // Both skeletons are sorted by field, so walk them side by side.
  case want, other {
    [], [] -> Distance(0, 0, 0)
    [a, ..rest], [b, ..more] if a.field == b.field ->
      compare(distance(rest, more, mask), a.field, masked(a, mask), b.kind)
    [a, ..rest], [b, ..] if a.field < b.field ->
      compare(distance(rest, other, mask), a.field, masked(a, mask), none)
    [a, ..rest], [] ->
      compare(distance(rest, other, mask), a.field, masked(a, mask), none)
    _, [b, ..more] -> compare(distance(want, more, mask), b.field, none, b.kind)
  }
}

@target(erlang)
fn masked(field: Field, mask: Int) -> Int {
  case int.bitwise_and(mask, int.bitwise_shift_left(1, field.field)) {
    0 -> none
    _ -> field.kind
  }
}

@target(erlang)
fn compare(d: Distance, field: Int, mine: Int, theirs: Int) -> Distance {
  let bit = int.bitwise_shift_left(1, field)
  case mine == theirs, mine == none, theirs == none {
    True, _, _ -> d
    False, True, _ ->
      Distance(
        d.distance + extra_field,
        d.missing,
        int.bitwise_or(d.extra, bit),
      )
    False, False, True ->
      Distance(
        d.distance + missing_field,
        int.bitwise_or(d.missing, bit),
        d.extra,
      )
    False, False, False ->
      Distance(
        d.distance + int.absolute_value(mine - theirs),
        d.missing,
        d.extra,
      )
  }
}

@target(erlang)
fn field_mask(skeleton: Skeleton) -> Int {
  list.fold(skeleton, 0, fn(m, f) {
    int.bitwise_or(m, int.bitwise_shift_left(1, f.field))
  })
}

// --- Matching ----------------------------------------------------------------

@target(erlang)
/// A stored pattern and the skeleton it's stored under. `specified` is set
/// when CLDR gave the skeleton.
pub opaque type Entry {
  Entry(skeleton: Skeleton, pattern: String, specified: Bool)
}

@target(erlang)
/// Makes an entry from a skeleton, like `"yMMMd"`, and its pattern.
pub fn entry(skeleton_text: String, pattern: String, specified: Bool) -> Entry {
  Entry(skeleton(skeleton_text), pattern, specified)
}

@target(erlang)
/// A locale's patterns and what joins them, in one calendar.
pub type Matcher {
  Matcher(
    entries: List(Entry),
    /// By field number.
    append_items: List(String),
    /// By field number.
    display_names: List(String),
    /// How to join a date and a time, from full to short.
    glues: List(String),
    default_hour_letter: String,
    decimal: String,
  )
}

@target(erlang)
type Best {
  Best(entry: Entry, missing: Int, extra: Int)
}

@target(erlang)
/// Like ICU's `getBestRaw`: the closest pattern, preferring ones missing less
/// significant fields.
fn best(m: Matcher, want: Skeleton, mask: Int) -> Result(Best, Nil) {
  closest(m.entries, want, mask, Error(Nil), 0)
}

@target(erlang)
fn closest(
  entries: List(Entry),
  want: Skeleton,
  mask: Int,
  found: Result(Best, Nil),
  found_distance: Int,
) -> Result(Best, Nil) {
  case entries, found {
    _, Ok(_) if found_distance == 0 -> found
    [], _ -> found
    [entry, ..rest], _ -> {
      let d = distance(want, entry.skeleton, mask)
      let better = case found {
        Error(Nil) -> True
        Ok(b) ->
          d.distance < found_distance
          || { d.distance == found_distance && b.missing < d.missing }
      }
      case better {
        True ->
          closest(
            rest,
            want,
            mask,
            Ok(Best(entry, d.missing, d.extra)),
            d.distance,
          )
        False -> closest(rest, want, mask, found, found_distance)
      }
    }
  }
}

@target(erlang)
fn specified(b: Best) -> Result(Skeleton, Nil) {
  case b.entry.specified {
    True -> Ok(b.entry.skeleton)
    False -> Error(Nil)
  }
}

@target(erlang)
/// Like ICU's `adjustFieldTypes`: gives the pattern's fields the requested
/// lengths. JavaScriptCore only asks for hour lengths to be kept.
fn adjust(
  m: Matcher,
  pattern: String,
  spec: Result(Skeleton, Nil),
  want: Skeleton,
  flags: Int,
) -> String {
  let all = items(pattern)
  adjust_items(m, all, all, spec, want, flags, "")
}

@target(erlang)
fn adjust_items(
  m: Matcher,
  all: List(String),
  rest: List(String),
  spec: Result(Skeleton, Nil),
  want: Skeleton,
  flags: Int,
  out: String,
) -> String {
  case rest {
    [] -> out
    ["'", ..] -> {
      let #(text, rest) = quote_literal(rest)
      adjust_items(m, all, rest, spec, want, flags, out <> text)
    }
    [item, ..rest] -> {
      let text = case is_separator(item, all) {
        True -> item
        False -> adjust_field(m, item, spec, want, flags)
      }
      adjust_items(m, all, rest, spec, want, flags, out <> text)
    }
  }
}

@target(erlang)
fn adjust_field(
  m: Matcher,
  item: String,
  spec: Result(Skeleton, Nil),
  want: Skeleton,
  flags: Int,
) -> String {
  case row(item) {
    Error(Nil) -> item
    Ok(r) -> {
      let f = r.field
      case int.bitwise_and(flags, fix_fractional_seconds) != 0 && f == second {
        True ->
          item
          <> m.decimal
          <> string.repeat("S", length(want, fractional_second))
        False ->
          case get(want, f) {
            Error(Nil) -> item
            Ok(wanted) -> resize(m, item, r, spec, wanted)
          }
      }
    }
  }
}

@target(erlang)
fn resize(
  m: Matcher,
  item: String,
  r: Row,
  spec: Result(Skeleton, Nil),
  wanted: Field,
) -> String {
  let f = r.field
  let requested = case wanted.letter, wanted.length < 3 {
    "E", True -> 3
    _, _ -> wanted.length
  }
  let keep = case f == minute || f == second, spec {
    True, _ -> True
    False, Ok(s) if wanted.letter != "c" && wanted.letter != "e" ->
      length(s, f) == requested || { r.kind > 0 } != { wanted.kind > 0 }
    False, _ -> False
  }
  let size = case keep {
    True -> string.length(item)
    False -> requested
  }
  let assert Ok(pattern_letter) = string.first(item)
  let letter = case f == hour || f == month || f == weekday, f == year {
    True, _ -> pattern_letter
    False, True if wanted.letter != "Y" -> pattern_letter
    False, _ -> wanted.letter
  }
  let letter = case letter, size < 3 {
    "E", True -> "e"
    _, _ -> letter
  }
  let letter = case f == hour {
    True -> hour_letter(m.default_hour_letter, letter, wanted.letter)
    False -> letter
  }
  string.repeat(letter, size)
}

@target(erlang)
/// ICU matches the hour letter to the locale's hour cycle.
fn hour_letter(locale: String, letter: String, wanted: String) -> String {
  case wanted == locale, wanted, locale {
    True, _, _ -> locale
    _, "h", "K" -> "K"
    _, "H", "k" -> "k"
    _, "k", "H" -> "H"
    _, "K", "h" -> "h"
    _, _, _ -> letter
  }
}

@target(erlang)
/// Like ICU's `mapSkeletonMetacharacters`, for the `j` JavaScriptCore uses.
fn map_metacharacters(m: Matcher, form: String) -> String {
  form
  |> items
  |> list.map(fn(run) {
    case string.first(run) {
      Ok("j") -> {
        let extra = string.length(run) - 1
        let hour_length = 1 + int.bitwise_and(extra, 1)
        let period_length = case extra < 2 {
          True -> 1
          False -> 3 + int.bitwise_shift_right(extra, 1)
        }
        let period_length = case m.default_hour_letter {
          "H" | "k" -> 0
          _ -> period_length
        }
        string.repeat("a", period_length)
        <> string.repeat(m.default_hour_letter, hour_length)
      }
      _ -> run
    }
  })
  |> string.concat
}

@target(erlang)
/// The highest field in a mask, like ICU's `getTopBitNumber`.
fn top_bit(mask: Int, i: Int) -> Int {
  case mask > 1 {
    True -> top_bit(int.bitwise_shift_right(mask, 1), i + 1)
    False -> int.min(i, zone)
  }
}

@target(erlang)
/// Like ICU's `getBestAppending`: finds patterns for the fields in `mask`,
/// joining any missing ones on with append items.
fn appending(m: Matcher, want: Skeleton, mask: Int) -> Result(String, Nil) {
  case mask {
    0 -> Ok("")
    _ -> {
      use first <- result_try(best(m, want, mask))
      let start = adjust(m, first.entry.pattern, specified(first), want, 0)
      append_missing(m, want, mask, start, first.missing, 0, specified(first))
    }
  }
}

@target(erlang)
fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(a) -> next(a)
    Error(e) -> Error(e)
  }
}

@target(erlang)
fn append_missing(
  m: Matcher,
  want: Skeleton,
  mask: Int,
  result: String,
  missing: Int,
  last: Int,
  spec: Result(Skeleton, Nil),
) -> Result(String, Nil) {
  let only_fraction =
    int.bitwise_and(missing, second_and_fractional_mask) == fractional_mask
    && int.bitwise_and(mask, second_and_fractional_mask)
    == second_and_fractional_mask
  case missing == 0 || missing == last, only_fraction {
    True, _ -> Ok(result)
    False, True ->
      append_missing(
        m,
        want,
        mask,
        adjust(m, result, spec, want, fix_fractional_seconds),
        int.bitwise_and(missing, int.bitwise_not(fractional_mask)),
        last,
        spec,
      )
    False, False -> {
      use next <- result_try(best(m, want, missing))
      let found = int.bitwise_and(missing, int.bitwise_not(next.missing))
      case found {
        // ICU would read before the start of its append items here.
        0 -> Error(Nil)
        _ -> {
          let top = top_bit(found, 0)
          let piece = adjust(m, next.entry.pattern, specified(next), want, 0)
          let result = case at(m.append_items, top) {
            "" -> result
            format ->
              simple_format(format, [
                result,
                piece,
                quote <> at(m.display_names, top) <> quote,
              ])
          }
          append_missing(
            m,
            want,
            mask,
            result,
            next.missing,
            next.missing,
            specified(next),
          )
        }
      }
    }
  }
}

@target(erlang)
fn at(items: List(String), index: Int) -> String {
  case list.drop(items, index) {
    [item, ..] -> item
    [] -> ""
  }
}

@target(erlang)
/// Like ICU's `SimpleFormatter`: fills in `{0}` and so on. An apostrophe
/// quotes braces, and two make one.
pub fn simple_format(pattern: String, args: List(String)) -> String {
  fill(characters(pattern), args, False, "")
}

@target(erlang)
fn fill(
  chars: List(String),
  args: List(String),
  quoted: Bool,
  out: String,
) -> String {
  case chars, quoted {
    [], _ -> out
    ["'", "'", ..rest], _ -> fill(rest, args, quoted, out <> quote)
    ["'", ..rest], True -> fill(rest, args, False, out)
    ["'", "{", ..], False | ["'", "}", ..], False -> {
      let assert [_, ..rest] = chars
      fill(rest, args, True, out)
    }
    ["{", digit, "}", ..rest], False ->
      case int.parse(digit) {
        Ok(n) -> fill(rest, args, quoted, out <> at(args, n))
        Error(Nil) -> fill(list.drop(chars, 1), args, quoted, out <> "{")
      }
    [c, ..rest], _ -> fill(rest, args, quoted, out <> c)
  }
}

@target(erlang)
const full = 0

@target(erlang)
const long_style = 1

@target(erlang)
const medium = 2

@target(erlang)
const short_style = 3

@target(erlang)
fn base_length(skeleton: Skeleton, field: Int) -> Int {
  case get(skeleton, field) {
    Ok(f) -> f.base_length
    Error(Nil) -> 0
  }
}

@target(erlang)
/// Like ICU's `getBestPattern`. It fails if ICU would read outside its data.
fn best_pattern(m: Matcher, form: String) -> Result(String, Nil) {
  let want = skeleton(map_metacharacters(m, form))
  use raw <- result_try(best(m, want, all_fields))
  case raw.missing == 0 && raw.extra == 0 {
    True -> Ok(adjust(m, raw.entry.pattern, specified(raw), want, 0))
    False -> {
      let needed = field_mask(want)
      use date <- result_try(appending(
        m,
        want,
        int.bitwise_and(needed, date_mask),
      ))
      use time <- result_try(appending(
        m,
        want,
        int.bitwise_and(needed, time_mask),
      ))
      let style = case
        base_length(want, month),
        base_length(want, weekday) > 0
      {
        4, True -> full
        4, False -> long_style
        3, _ -> medium
        _, _ -> short_style
      }
      case date, time {
        "", _ -> Ok(time)
        _, "" -> Ok(date)
        _, _ -> Ok(simple_format(at(m.glues, style), [time, date]))
      }
    }
  }
}

// --- JavaScriptCore ----------------------------------------------------------

@target(erlang)
fn name_length(width: String) -> Int {
  case width {
    "narrow" -> 5
    "short" -> 3
    "long" -> 4
    _ -> 0
  }
}

@target(erlang)
fn digits_length(digits: String) -> Int {
  case digits {
    "numeric" -> 1
    "2-digit" -> 2
    _ -> 0
  }
}

@target(erlang)
fn month_length(width: String) -> Int {
  case digits_length(width) {
    0 -> name_length(width)
    n -> n
  }
}

@target(erlang)
/// JavaScriptCore asks for a short day period with one letter.
fn day_period_length(width: String) -> Int {
  case width {
    "short" -> 1
    _ -> name_length(width)
  }
}

@target(erlang)
fn zone_letters(name: String) -> String {
  case name {
    "short" -> "z"
    "long" -> "zzzz"
    "shortOffset" -> "O"
    "longOffset" -> "OOOO"
    "shortGeneric" -> "v"
    "longGeneric" -> "vvvv"
    _ -> ""
  }
}

@target(erlang)
/// JavaScriptCore's `buildSkeleton`, without defaults.
fn jsc_skeleton(r: Request) -> String {
  let hour_letter = case r.hour_cycle {
    "" -> "j"
    "h11" | "h12" -> "h"
    _ -> "H"
  }
  string.concat([
    string.repeat("E", name_length(r.weekday)),
    string.repeat("G", name_length(r.era)),
    string.repeat("y", digits_length(r.year)),
    string.repeat("M", month_length(r.month)),
    string.repeat("d", digits_length(r.day)),
    string.repeat(hour_letter, digits_length(r.hour)),
    string.repeat("B", day_period_length(r.day_period)),
    string.repeat("m", digits_length(r.minute)),
    string.repeat("s", digits_length(r.second)),
    string.repeat("S", r.fractional_second_digits),
    zone_letters(r.time_zone_name),
  ])
}

@target(erlang)
fn is_hour_letter(c: String) -> Bool {
  c == "h" || c == "H" || c == "k" || c == "K"
}

@target(erlang)
/// JavaScriptCore's `replaceHourCycleInPattern`: uses the hour cycle's
/// letter, and makes a lone 12 hour letter two long for a 24 hour clock.
fn replace_hour_cycle(pattern: String, cycle: String) -> String {
  case cycle {
    "" -> pattern
    _ -> {
      let to = case cycle {
        "h11" -> "K"
        "h12" -> "h"
        "h23" -> "H"
        _ -> "k"
      }
      let to24 = cycle == "h23" || cycle == "h24"
      replace_hours(characters(pattern), "", to, to24, "")
    }
  }
}

@target(erlang)
fn replace_hours(
  chars: List(String),
  before: String,
  to: String,
  to24: Bool,
  out: String,
) -> String {
  case chars {
    [] -> out
    ["'", ..rest] -> {
      let #(text, rest) = skip_quoted(rest, quote)
      replace_hours(rest, quote, to, to24, out <> text)
    }
    [c, ..rest] ->
      case is_hour_letter(c) {
        False -> replace_hours(rest, c, to, to24, out <> c)
        True -> {
          let after = case rest {
            [next, ..] -> is_hour_letter(next)
            [] -> False
          }
          let lone =
            to24
            && { c == "h" || c == "K" }
            && !is_hour_letter(before)
            && !after
          let written = case lone {
            True -> to <> to
            False -> to
          }
          replace_hours(rest, c, to, to24, out <> written)
        }
      }
  }
}

@target(erlang)
fn skip_quoted(chars: List(String), text: String) -> #(String, List(String)) {
  case chars {
    [] -> #(text, [])
    ["'", ..rest] -> #(text <> quote, rest)
    [c, ..rest] -> skip_quoted(rest, text <> c)
  }
}

@target(erlang)
/// The pattern JavaScriptCore formats with for some fields.
pub fn pattern(m: Matcher, r: Request) -> Result(String, Nil) {
  use found <- result_try(best_pattern(m, jsc_skeleton(r)))
  Ok(replace_hour_cycle(found, r.hour_cycle))
}

// --- Pieces ------------------------------------------------------------------

@target(erlang)
/// A piece of a pattern: text, or a run of one letter like `MMM`.
pub type Piece {
  Text(String)
  Run(letter: String, length: Int)
}

@target(erlang)
/// Splits a pattern the way ICU's SimpleDateFormat reads it. Two apostrophes
/// make one, and text between apostrophes is quoted. JavaScriptCore writes
/// narrow and thin spaces as plain ones.
pub fn pieces(pattern: String) -> List(Piece) {
  split(characters(pattern), False, [])
}

@target(erlang)
fn split(chars: List(String), quoted: Bool, out: List(Piece)) -> List(Piece) {
  case chars {
    [] -> list.reverse(out)
    ["'", "'", ..rest] -> split(rest, quoted, add_text(out, quote))
    ["'", ..rest] -> split(rest, !quoted, out)
    [c, ..rest] ->
      case quoted || !is_letter(c) {
        True -> split(rest, quoted, add_text(out, jsc_text(c)))
        False -> {
          let same = list.take_while(rest, fn(d) { d == c })
          let n = list.length(same)
          split(list.drop(rest, n), quoted, [Run(c, n + 1), ..out])
        }
      }
  }
}

@target(erlang)
fn add_text(out: List(Piece), text: String) -> List(Piece) {
  case out {
    [Text(last), ..rest] -> [Text(last <> text), ..rest]
    _ -> [Text(text), ..out]
  }
}

@target(erlang)
fn jsc_text(c: String) -> String {
  case c {
    "\u{202F}" | "\u{2009}" -> " "
    _ -> c
  }
}

@target(erlang)
const has_han_year = 1

@target(erlang)
const has_era = 2

@target(erlang)
const has_minutes = 4

@target(erlang)
/// The flags in a run's key, like `runKey` in `codegen/matcher.ts`, for
/// tokens that depend on their pattern:
///
/// - ICU writes Japanese year 1 as 元 when the pattern has 年 anywhere.
/// - JavaScriptCore changes years in some calendars when the pattern has an
///   era.
/// - ICU says noon all through 12 o'clock unless the pattern shows minutes or
///   seconds.
pub fn run_flags(letter: String, pattern: String, pieces: List(Piece)) -> Int {
  case letter {
    "y" -> {
      let han = case string.contains(pattern, "年") {
        True -> has_han_year
        False -> 0
      }
      let era = case has_era_run(pieces) {
        True -> has_era
        False -> 0
      }
      han + era
    }
    "b" | "B" ->
      case has_run(pieces, fn(l) { l == "m" || l == "s" }) {
        True -> has_minutes
        False -> 0
      }
    _ -> 0
  }
}

@target(erlang)
/// Whether a pattern's pieces have an era.
pub fn has_era_run(pieces: List(Piece)) -> Bool {
  has_run(pieces, fn(l) { l == "G" })
}

@target(erlang)
fn has_run(pieces: List(Piece), letter: fn(String) -> Bool) -> Bool {
  list.any(pieces, fn(piece) {
    case piece {
      Run(letter: l, ..) -> letter(l)
      Text(_) -> False
    }
  })
}

@target(erlang)
/// Whether text ends in a character Unicode calls white space. JavaScriptCore
/// checks this before it adds its own era.
pub fn ends_with_space(text: String) -> Bool {
  case list.last(characters(text)) {
    Ok(c) -> is_space(c)
    Error(Nil) -> False
  }
}

@target(erlang)
fn is_space(c: String) -> Bool {
  case c {
    "\t" | "\n" | "\u{0B}" | "\u{0C}" | "\r" | " " | "\u{85}" | "\u{A0}" -> True
    "\u{1680}" | "\u{2028}" | "\u{2029}" | "\u{202F}" | "\u{205F}" -> True
    "\u{3000}" -> True
    "\u{2000}"
    | "\u{2001}"
    | "\u{2002}"
    | "\u{2003}"
    | "\u{2004}"
    | "\u{2005}" -> True
    "\u{2006}" | "\u{2007}" | "\u{2008}" | "\u{2009}" | "\u{200A}" -> True
    _ -> False
  }
}

@target(erlang)
/// JavaScriptCore's era workaround. Bun's JavaScriptCore writes its own era
/// before a set instant, because ICU never picks that era. For Islamic
/// calendars it replaces ICU's era and writes the year as 1 minus ICU's, in
/// ASCII digits. Coptic's first era has no name in ICU, so JavaScriptCore adds
/// its era to the end. JavaScriptCore applies the workaround only when the
/// pattern has an era.
/// `codegen/matcher.ts` does the same.
pub type EraWorkaround {
  NoEraWorkaround
  Replaces(before_ms: Int, text: String)
  Appends(before_ms: Int, text: String)
}

@target(erlang)
/// Picks the era workaround for a calendar from ICU's name for it, like
/// `"coptic"`.
pub fn era_workaround(calendar: String) -> EraWorkaround {
  case calendar {
    "islamic-civil" | "islamic-umalqura" ->
      Replaces(-42_521_558_822_000, "Before Hijra")
    "islamic-tbla" -> Replaces(-42_521_645_222_000, "Before Hijra")
    "coptic" -> Appends(-53_184_182_822_000, "Anno Martyrum")
    _ -> NoEraWorkaround
  }
}

@target(erlang)
/// Splits text into code points, like ICU, so an apostrophe with an accent on
/// it still counts as an apostrophe.
fn characters(text: String) -> List(String) {
  text
  |> string.to_utf_codepoints
  |> list.map(fn(point) { string.from_utf_codepoints([point]) })
}
