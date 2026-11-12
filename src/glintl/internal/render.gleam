//// Formats timestamps on Erlang with the tables that `codegen/pack.ts` writes
//// to `glintl_generated_data`. The JavaScript target uses only `Shown`.
////
//// The tables store each distinct token once, and a pattern is a list of its
//// tokens' numbers. A formatter points at these literals instead of copying
//// them.

@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
import glintl/internal/data
@target(erlang)
import glintl/internal/matcher
@target(erlang)
import glintl/internal/zones

/// What a formatter shows.
pub type Shown {
  DateOnly(data.Style)
  TimeOnly(data.Style)
  DateAndTime(date: data.Style, time: data.Style)
}

@target(erlang)
pub const seconds_per_minute = 60

@target(erlang)
const seconds_per_hour = 3600

@target(erlang)
pub const seconds_per_day = 86_400

@target(erlang)
/// The longest a year can be in a calendar with Gregorian months.
const days_in_longest_year = 366

@target(erlang)
const hours_per_half_day = 12

@target(erlang)
const hours_per_day = 24

@target(erlang)
/// 1970-01-01 was a Thursday, and weekdays are numbered from Sunday.
const thursday = 4

@target(erlang)
/// Two digit years show the year modulo this.
const two_digit_years = 100

@target(erlang)
const ten = 10

@target(erlang)
/// Pattern numbers in formats are this many bytes.
const number_bytes = 2

@target(erlang)
const style_count = 4

@target(erlang)
/// Formats are stored by style, in this order.
const styles = [data.Full, data.Long, data.Medium, data.Short]

@target(erlang)
type HourCycle {
  /// 0 to 11.
  H11
  /// 1 to 12.
  H12
  /// 0 to 23.
  H23
  /// 1 to 24.
  H24
}

@target(erlang)
/// A pattern in the packed data.
type Pattern {
  /// `tokens` are 16-bit numbers in the tokens table.
  Pattern(has_minute: Bool, has_second: Bool, tokens: BitArray)
}

@target(erlang)
type Token {
  Literal(String)
  /// A part written with ASCII digits, whatever the locale's digits are.
  AsciiDigits(Token)
  /// `first` and `minus_first` are names for years 1 and -1, like 元, or "".
  /// `min_digits` is the fewest digits a year shows, like ICU's `yyyy`
  /// showing year 1 as "0001".
  Year(
    two_digit: Bool,
    min_digits: Int,
    minus: String,
    first: String,
    minus_first: String,
  )
  /// ICU's week-based year.
  WeekYear(
    minus: String,
    two_digit: Bool,
    min_digits: Int,
    first_day: Int,
    minimal_days: Int,
    exceptions: List(#(Int, Int)),
  )
  ExtendedYear(minus: String, two_digit: Bool)
  /// `pad` writes related years under ten with two digits.
  RelatedYear(pad: Bool)
  /// The Chinese and Dangi era: which 60 year cycle the year is in.
  CycleEra
  YearName(Names)
  MonthName(Names)
  DayName(Names)
  Weekday(Names)
  Era(Names)
  MonthNumber(pad: Bool)
  Day(pad: Bool)
  Minute(pad: Bool)
  Second(pad: Bool)
  /// The first `digits` digits of the fraction of a second, cut off without
  /// rounding.
  Fraction(digits: Int)
  Hour(pad: Bool, cycle: HourCycle)
  DayPeriod(by_hour: Names, midnight: String, noon: String)
  Zone(
    names: ZoneNameStyle,
    zero: String,
    positive: String,
    positive_suffix: String,
    positive_whole_suffix: String,
    negative: String,
    negative_suffix: String,
    negative_whole_suffix: String,
    pad_hours: Bool,
    separator: String,
    optional_minutes: Bool,
  )
  GlueDate
  GlueTime
}

@target(erlang)
/// Whether a zone token shows a named zone's name, like ICU's `z` and `zzzz`.
/// Fixed offsets, and zones with no name in the locale, show the offset.
type ZoneNameStyle {
  OnlyOffset
  ShortNames
  LongNames
}

@target(erlang)
type Names =
  data.HomogenousUnknownLengthTuple(String)

@target(erlang)
/// A formatter's patterns, ready to render.
pub opaque type Compiled {
  Compiled(
    main: Prepared,
    /// Patterns for eras that ICU formats differently.
    eras: List(#(Int, Prepared)),
    digits: Digits,
    days: Days,
  )
}

@target(erlang)
/// The digits a locale writes numbers with.
type Digits {
  Ascii
  /// The locale's ten digits, from zero to nine.
  Local(Names)
}

@target(erlang)
/// How a formatter turns a day into a date.
type Days {
  /// The Gregorian calendar, which covers every day.
  GregorianDays
  /// Another calendar, which falls back to Gregorian for days outside its
  /// years. glintl builds both when needed, so a copied formatter stays small.
  OtherDays(math: fn() -> data.Math, gregorian: fn() -> Compiled)
}

@target(erlang)
/// Tokens to render. In a glue pattern, `date` and `time` are what it joins.
type Prepared {
  Prepared(
    has_minute: Bool,
    has_second: Bool,
    tokens: BitArray,
    date: BitArray,
    time: BitArray,
  )
  /// A pattern for fields, worked out when the formatter is compiled. Each
  /// piece has its run's letter, or `""` for text.
  Listed(
    has_minute: Bool,
    has_second: Bool,
    pieces: List(#(String, Token)),
    workaround: Workaround,
  )
}

@target(erlang)
/// JavaScriptCore's era workaround, which `matcher.era_workaround` explains.
type Workaround {
  NoWorkaround
  /// Replace the last era and year before `before_ms`.
  ReplaceEra(before_ms: Int, text: String, two_digit_year: Bool)
  /// Before `before_ms`, leave out the era and add `text` to the end.
  AppendEra(before_ms: Int, text: String)
}

// --- Tables ------------------------------------------------------------------

@target(erlang)
@external(erlang, "glintl_generated_data", "tokens")
fn tokens() -> data.HomogenousUnknownLengthTuple(Token)

@target(erlang)
@external(erlang, "glintl_generated_data", "digits")
fn digits_table() -> data.HomogenousUnknownLengthTuple(Names)

@target(erlang)
@external(erlang, "glintl_generated_data", "patterns")
fn patterns() -> data.HomogenousUnknownLengthTuple(Pattern)

@target(erlang)
@external(erlang, "glintl_generated_data", "formats")
fn formats() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "locales")
fn locales() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "fields")
fn fields() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "field_entries")
fn field_entries() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "field_texts")
fn field_texts() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "field_runs")
fn field_runs() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
@external(erlang, "glintl_generated_data", "field_strings")
fn field_strings() -> data.HomogenousUnknownLengthTuple(String)

@target(erlang)
@external(erlang, "erlang", "element")
fn element(index: Int, tuple: data.HomogenousUnknownLengthTuple(a)) -> a

@target(erlang)
@external(erlang, "erlang", "tuple_size")
fn tuple_size(tuple: data.HomogenousUnknownLengthTuple(a)) -> Int

@target(erlang)
/// The number at `index` in packed 16-bit numbers.
fn number_at(bits: BitArray, index: Int) -> Int {
  case bits {
    <<_:bytes-size(index * number_bytes), n:16, _:bits>> -> n
    _ -> 0
  }
}

// --- Compiling ---------------------------------------------------------------

@target(erlang)
/// Each calendar has its formats, then its formats in each hour cycle.
const formats_per_calendar = 5

@target(erlang)
/// A locale entry starts with its digits number and its default hour cycle.
const entry_header = 2

@target(erlang)
/// The default hour cycle of a locale, as a position in `HOUR_CYCLES` in
/// `codegen/patterns.ts`.
pub fn default_hour_cycle(locale: Int) -> Int {
  number_at(element(locale, locales()), 1)
}

@target(erlang)
/// A formatter for a locale's Gregorian formats. `cycle` is 0 for the
/// locale's own hour cycle, or 1 more than a position in `HOUR_CYCLES`.
pub fn compile(locale: Int, cycle: Int, shown: Shown) -> Compiled {
  let entry = element(locale, locales())
  compile_formats(entry, 0, cycle, shown, GregorianDays)
}

@target(erlang)
/// A formatter for the calendar at `position` in the locale's formats. It
/// falls back to Gregorian outside the calendar's years.
pub fn compile_other(
  locale: Int,
  position: Int,
  cycle: Int,
  math: fn() -> data.Math,
  shown: Shown,
) -> Compiled {
  let entry = element(locale, locales())
  let gregorian = fn() {
    compile_formats(entry, 0, cycle, shown, GregorianDays)
  }
  compile_formats(entry, position, cycle, shown, OtherDays(math:, gregorian:))
}

@target(erlang)
fn compile_formats(
  entry: BitArray,
  position: Int,
  cycle: Int,
  shown: Shown,
  days: Days,
) -> Compiled {
  let digits = digits_of(number_at(entry, 0))
  let index = entry_header + position * formats_per_calendar + cycle
  let formats = element(number_at(entry, index), formats())
  let #(dates, formats) = split(formats)
  let #(times, formats) = split(formats)
  let #(glues, formats) = split(formats)
  let each = style_count * number_bytes
  let #(combined, formats) = case formats {
    <<1, combined:bytes-size(each * style_count), rest:bits>> -> #(
      combined,
      rest,
    )
    <<_, rest:bits>> -> #(<<>>, rest)
    _ -> #(<<>>, <<>>)
  }
  let main = prepare(dates, times, glues, combined, shown)
  let eras = case shown, formats {
    TimeOnly(_), _ -> []
    _, <<count, eras:bits>> -> eras_of(eras, count, times, glues, shown)
    _, _ -> []
  }
  Compiled(main:, eras:, digits:, days:)
}

@target(erlang)
/// After every calendar's formats, each calendar has a number in `fields`.
const fields_per_calendar = 1

@target(erlang)
/// How many fields there are. Texts hold the append items and display names
/// for each field, the glues for each style, then the decimal separator.
const field_count = 16

@target(erlang)
/// A formatter for fields in the calendar at `position`. Calendars other than
/// Gregorian fall back to Gregorian outside their years.
pub fn compile_fields(
  locale: Int,
  position: Int,
  request: matcher.Request,
  calendar: String,
  math: fn() -> data.Math,
) -> Compiled {
  let gregorian = fn() {
    compile_fields_at(
      locale,
      0,
      request,
      matcher.NoEraWorkaround,
      GregorianDays,
    )
  }
  case position {
    0 -> gregorian()
    _ ->
      compile_fields_at(
        locale,
        position,
        request,
        matcher.era_workaround(calendar),
        OtherDays(math:, gregorian:),
      )
  }
}

@target(erlang)
fn compile_fields_at(
  locale: Int,
  position: Int,
  request: matcher.Request,
  workaround: matcher.EraWorkaround,
  days: Days,
) -> Compiled {
  let entry = element(locale, locales())
  let numbers = bit_array_byte_size(entry) / number_bytes
  let calendars =
    { numbers - entry_header } / { formats_per_calendar + fields_per_calendar }
  let digits = digits_of(number_at(entry, 0))
  let row =
    element(
      number_at(
        entry,
        entry_header + calendars * formats_per_calendar + position,
      ),
      fields(),
    )
  // The hour letter, the entries, the texts, then the runs for each field.
  let assert <<hour_letter, entries_id:16, texts_id:16, runs:bits>> = row
  let texts = strings(element(texts_id, field_texts()))
  let m =
    matcher.Matcher(
      entries: entries(element(entries_id, field_entries())),
      append_items: list.take(texts, field_count),
      display_names: list.take(list.drop(texts, field_count), field_count),
      glues: list.take(list.drop(texts, 2 * field_count), style_count),
      default_hour_letter: from_codepoint(hour_letter),
      decimal: at(list.drop(texts, 2 * field_count + style_count), 0, ""),
    )
  let main = case matcher.pattern(m, request) {
    Ok(pattern) -> listed(pattern, runs, request, workaround)
    Error(Nil) -> Error(Nil)
  }
  case main {
    Ok(main) -> Compiled(main:, eras: [], digits:, days:)
    // The generator checks every request each locale can get, so only a bug
    // in glintl reaches this.
    Error(Nil) -> panic as "glintl found no pattern for these fields"
  }
}

@target(erlang)
fn listed(
  pattern: String,
  runs: BitArray,
  request: matcher.Request,
  workaround: matcher.EraWorkaround,
) -> Result(Prepared, Nil) {
  let pieces = matcher.pieces(pattern)
  let tokens =
    list.try_map(pieces, fn(piece) {
      case piece {
        matcher.Text(text) -> Ok(#("", Literal(text)))
        matcher.Run(letter:, length:) -> {
          let flags = matcher.run_flags(letter, pattern, pieces)
          case
            find_run(
              field_runs_for(runs, letter),
              to_codepoint(letter),
              length,
              flags,
            )
          {
            Ok(id) -> Ok(#(letter, element(id, tokens())))
            Error(Nil) -> Error(Nil)
          }
        }
      }
    })
  case tokens {
    Error(Nil) -> Error(Nil)
    Ok(tokens) -> {
      let has_era = matcher.has_era_run(pieces)
      let workaround = case workaround, has_era {
        matcher.Replaces(before_ms:, text:), True ->
          ReplaceEra(
            before_ms:,
            text:,
            two_digit_year: request.year == "2-digit",
          )
        matcher.Appends(before_ms:, text:), True -> AppendEra(before_ms:, text:)
        _, _ -> NoWorkaround
      }
      Ok(Listed(
        pieces: tokens,
        has_minute: list.any(tokens, fn(t) { is_minute(t.1) }),
        has_second: list.any(tokens, fn(t) { is_second(t.1) }),
        workaround:,
      ))
    }
  }
}

@target(erlang)
fn is_minute(token: Token) -> Bool {
  case token {
    Minute(_) -> True
    AsciiDigits(inner) -> is_minute(inner)
    _ -> False
  }
}

@target(erlang)
fn is_second(token: Token) -> Bool {
  case token {
    Second(_) -> True
    AsciiDigits(inner) -> is_second(inner)
    _ -> False
  }
}

@target(erlang)
/// The runs of a letter's field, from a fields entry's run numbers.
fn field_runs_for(runs: BitArray, letter: String) -> BitArray {
  case matcher.field_of(letter) {
    Ok(field) ->
      case runs {
        <<_:bytes-size(field * number_bytes), id:16, _:bits>> ->
          element(id, field_runs())
        _ -> <<>>
      }
    Error(Nil) -> <<>>
  }
}

@target(erlang)
/// A run's token number. Runs are each a letter, a length and flags, then
/// a 16-bit token number.
fn find_run(
  runs: BitArray,
  letter: Int,
  length: Int,
  flags: Int,
) -> Result(Int, Nil) {
  case runs {
    <<l, n, f, id:16, _:bits>> if l == letter && n == length && f == flags ->
      Ok(id)
    <<_, _, _, _:16, rest:bits>> -> find_run(rest, letter, length, flags)
    _ -> Error(Nil)
  }
}

@target(erlang)
/// Each stored pattern's skeleton and pattern numbers, then 1 if CLDR gave
/// the skeleton.
fn entries(bits: BitArray) -> List(matcher.Entry) {
  case bits {
    <<skeleton:16, pattern:16, specified, rest:bits>> -> [
      matcher.entry(
        element(skeleton, field_strings()),
        element(pattern, field_strings()),
        specified == 1,
      ),
      ..entries(rest)
    ]
    _ -> []
  }
}

@target(erlang)
fn strings(bits: BitArray) -> List(String) {
  case bits {
    <<id:16, rest:bits>> -> [element(id, field_strings()), ..strings(rest)]
    _ -> []
  }
}

@target(erlang)
fn at(items: List(a), index: Int, otherwise: a) -> a {
  case list.drop(items, index) {
    [item, ..] -> item
    [] -> otherwise
  }
}

@target(erlang)
fn to_codepoint(letter: String) -> Int {
  case string_to_codepoints(letter) {
    [n, ..] -> n
    [] -> 0
  }
}

@target(erlang)
@external(erlang, "unicode", "characters_to_list")
fn string_to_codepoints(text: String) -> List(Int)

@target(erlang)
fn from_codepoint(n: Int) -> String {
  codepoints_to_string([n])
}

@target(erlang)
@external(erlang, "unicode", "characters_to_binary")
fn codepoints_to_string(codepoints: List(Int)) -> String

@target(erlang)
@external(erlang, "erlang", "byte_size")
fn bit_array_byte_size(bits: BitArray) -> Int

@target(erlang)
/// Splits off a pattern number for each style.
fn split(bits: BitArray) -> #(BitArray, BitArray) {
  case bits {
    <<each:bytes-size(style_count * number_bytes), rest:bits>> -> #(each, rest)
    _ -> #(<<>>, <<>>)
  }
}

@target(erlang)
/// `codegen/pack.ts` writes each era as its number, its date patterns, then a
/// byte for how it joins dates to times. 0 uses the usual glues, 1 is followed
/// by a pattern for each date and time style, and 2 by the era's own glues.
fn eras_of(
  bits: BitArray,
  count: Int,
  times: BitArray,
  glues: BitArray,
  shown: Shown,
) -> List(#(Int, Prepared)) {
  let each = style_count * number_bytes
  case count, bits {
    0, _ -> []
    _,
      <<
        era,
        dates:bytes-size(each),
        1,
        both:bytes-size(each * style_count),
        rest:bits,
      >>
    -> [
      #(era, prepare(dates, times, glues, both, shown)),
      ..eras_of(rest, count - 1, times, glues, shown)
    ]
    _, <<era, dates:bytes-size(each), 2, own:bytes-size(each), rest:bits>> -> [
      #(era, prepare(dates, times, own, <<>>, shown)),
      ..eras_of(rest, count - 1, times, glues, shown)
    ]
    _, <<era, dates:bytes-size(each), _, rest:bits>> -> [
      #(era, prepare(dates, times, glues, <<>>, shown)),
      ..eras_of(rest, count - 1, times, glues, shown)
    ]
    _, _ -> []
  }
}

@target(erlang)
/// `combined` has a pattern for each pair of date and time styles. It's empty
/// when ICU joins the date and time with a glue pattern.
fn prepare(
  dates: BitArray,
  times: BitArray,
  glues: BitArray,
  combined: BitArray,
  shown: Shown,
) -> Prepared {
  let pick = fn(bits, style) {
    element(number_at(bits, position(style)), patterns())
  }
  case shown, combined {
    TimeOnly(time), _ -> single(pick(times, time))
    DateOnly(date), _ -> single(pick(dates, date))
    DateAndTime(date:, time:), <<>> -> {
      let Pattern(tokens: glue, ..) = pick(glues, date)
      let Pattern(tokens: date_tokens, has_minute:, has_second:) =
        pick(dates, date)
      let time_pattern = pick(times, time)
      Prepared(
        tokens: glue,
        date: date_tokens,
        time: time_pattern.tokens,
        has_minute: has_minute || time_pattern.has_minute,
        has_second: has_second || time_pattern.has_second,
      )
    }
    DateAndTime(date:, time:), _ -> {
      let index = position(date) * style_count + position(time)
      single(element(number_at(combined, index), patterns()))
    }
  }
}

@target(erlang)
fn single(pattern: Pattern) -> Prepared {
  Prepared(
    tokens: pattern.tokens,
    date: <<>>,
    time: <<>>,
    has_minute: pattern.has_minute,
    has_second: pattern.has_second,
  )
}

@target(erlang)
fn position(style: data.Style) -> Int {
  index_of(styles, style, 0)
}

@target(erlang)
fn index_of(items: List(a), item: a, index: Int) -> Int {
  case items {
    [first, ..] if first == item -> index
    [_, ..rest] -> index_of(rest, item, index + 1)
    [] -> index
  }
}

// --- Rendering ---------------------------------------------------------------

@target(erlang)
pub fn render(
  compiled: Compiled,
  unix_seconds: Int,
  milliseconds: Int,
  offset_seconds: Int,
  names: data.ZoneNames,
) -> String {
  case compiled.days {
    GregorianDays ->
      write(
        compiled,
        gregorian_local(unix_seconds, offset_seconds, names),
        milliseconds,
      )
    OtherDays(math:, gregorian:) ->
      case local(math(), unix_seconds, offset_seconds, names) {
        Ok(local) -> write(compiled, local, milliseconds)
        Error(Nil) ->
          render(gregorian(), unix_seconds, milliseconds, offset_seconds, names)
      }
  }
}

@target(erlang)
fn write(compiled: Compiled, local: data.Local, milliseconds: Int) -> String {
  let prepared = case compiled.eras {
    [] -> compiled.main
    eras ->
      case key_find(eras, local.era) {
        Ok(prepared) -> prepared
        Error(Nil) -> compiled.main
      }
  }
  case prepared {
    Prepared(tokens:, ..) ->
      walk(tokens, prepared, local, milliseconds, compiled.digits, "")
    Listed(pieces:, workaround:, ..) -> {
      let texts =
        list.map(pieces, fn(piece) {
          #(
            piece.0,
            text(piece.1, prepared, local, milliseconds, compiled.digits),
          )
        })
      with_workaround(texts, workaround, local, milliseconds)
    }
  }
}

@target(erlang)
const milliseconds_per_second = 1000

@target(erlang)
/// Applies JavaScriptCore's era workaround to each piece's text.
fn with_workaround(
  texts: List(#(String, String)),
  workaround: Workaround,
  m: data.Local,
  milliseconds: Int,
) -> String {
  let ms = m.unix_seconds * milliseconds_per_second + milliseconds
  case workaround {
    ReplaceEra(before_ms:, text:, two_digit_year:) if ms < before_ms -> {
      let era = last_index(texts, "G", 0, -1)
      let year = last_index(texts, "y", 0, -1)
      texts
      |> list.index_map(fn(piece, i) {
        case i == era, i == year {
          True, _ -> text
          _, True -> flipped_year(m.extended, two_digit_year)
          _, _ -> piece.1
        }
      })
      |> string_concat
    }
    AppendEra(before_ms:, text:) if ms < before_ms -> {
      let written =
        texts
        |> list.map(fn(piece) {
          case piece.0 {
            "G" -> ""
            _ -> piece.1
          }
        })
        |> string_concat
      case matcher.ends_with_space(written) {
        True -> written <> text
        False -> written <> " " <> text
      }
    }
    _ -> string_concat(list.map(texts, fn(piece) { piece.1 }))
  }
}

@target(erlang)
fn last_index(
  texts: List(#(String, String)),
  letter: String,
  i: Int,
  found: Int,
) -> Int {
  case texts {
    [] -> found
    [#(l, _), ..rest] if l == letter -> last_index(rest, letter, i + 1, i)
    [_, ..rest] -> last_index(rest, letter, i + 1, found)
  }
}

@target(erlang)
/// JavaScriptCore writes 1 minus ICU's year, in ASCII digits.
fn flipped_year(icu_year: Int, two_digit: Bool) -> String {
  let flipped = 1 - icu_year
  case two_digit {
    True -> {
      let n = modulo(flipped, two_digit_years)
      case n < ten {
        True -> "0" <> int.to_string(n)
        False -> int.to_string(n)
      }
    }
    False -> int.to_string(flipped)
  }
}

@target(erlang)
@external(erlang, "erlang", "iolist_to_binary")
fn string_concat(strings: List(String)) -> String

@target(erlang)
fn key_find(pairs: List(#(Int, a)), key: Int) -> Result(a, Nil) {
  case pairs {
    [#(k, value), ..] if k == key -> Ok(value)
    [_, ..rest] -> key_find(rest, key)
    [] -> Error(Nil)
  }
}

@target(erlang)
fn walk(
  bits: BitArray,
  p: Prepared,
  m: data.Local,
  milliseconds: Int,
  digits: Digits,
  acc: String,
) -> String {
  case bits {
    <<id:16, rest:bits>> -> {
      let acc = case element(id, tokens()), p {
        GlueDate, Prepared(date:, ..) ->
          walk(date, p, m, milliseconds, digits, acc)
        GlueTime, Prepared(time:, ..) ->
          walk(time, p, m, milliseconds, digits, acc)
        token, _ -> acc <> text(token, p, m, milliseconds, digits)
      }
      walk(rest, p, m, milliseconds, digits, acc)
    }
    _ -> acc
  }
}

@target(erlang)
fn text(
  token: Token,
  p: Prepared,
  m: data.Local,
  milliseconds: Int,
  digits: Digits,
) -> String {
  case token {
    Literal(text) -> text
    AsciiDigits(inner) -> text(inner, p, m, milliseconds, Ascii)
    Year(two_digit: True, minus:, ..) -> {
      let sign = case m.year < 0 {
        True -> minus
        False -> ""
      }
      sign <> number(int.absolute_value(m.year) % two_digit_years, True, digits)
    }
    Year(two_digit: False, min_digits:, minus:, first:, minus_first:) -> {
      // Year 1 and -1 can have a name, like 元.
      let named = case m.year {
        1 -> first
        -1 -> minus_first
        _ -> ""
      }
      case named, m.year < 0 {
        "", False -> padded(m.year, min_digits, digits)
        "", True -> minus <> padded(-m.year, min_digits, digits)
        named, _ -> named
      }
    }
    WeekYear(
      minus:,
      two_digit:,
      min_digits:,
      first_day:,
      minimal_days:,
      exceptions:,
    ) -> {
      let year = data.week_year(m, first_day, minimal_days, exceptions)
      case two_digit, year < 0 {
        False, False -> padded(year, min_digits, digits)
        False, True -> minus <> padded(-year, min_digits, digits)
        True, True ->
          minus
          <> number(int.absolute_value(year) % two_digit_years, True, digits)
        True, False -> number(year % two_digit_years, True, digits)
      }
    }
    ExtendedYear(minus:, two_digit: False) -> signed(m.extended, minus, digits)
    ExtendedYear(minus:, two_digit: True) -> {
      let sign = case m.extended < 0 {
        True -> minus
        False -> ""
      }
      sign
      <> number(int.absolute_value(m.extended) % two_digit_years, True, digits)
    }
    RelatedYear(pad:) ->
      case m.related < 0 {
        True -> "-" <> number(-m.related, pad, digits)
        False -> number(m.related, pad, digits)
      }
    CycleEra -> number(data.cycle_era(m.related), False, digits)
    YearName(names) -> pick(names, m.cycle, m.cycle + 1, digits)
    MonthName(names) -> pick(names, m.month, m.month + 1, digits)
    DayName(names) -> pick(names, m.day, m.day, digits)
    Weekday(names) -> {
      let weekday = modulo(m.epoch_day + thursday, data.days_per_week)
      pick(names, weekday, weekday, digits)
    }
    Era(names) -> pick(names, m.era, m.era, digits)
    MonthNumber(pad:) -> number(m.month + 1, pad, digits)
    Day(pad:) -> number(m.day, pad, digits)
    Minute(pad:) -> number(m.minute, pad, digits)
    Second(pad:) -> number(m.second, pad, digits)
    Fraction(digits: shown) -> fraction(milliseconds, shown, digits)
    Hour(pad:, cycle:) -> number(hour(m.hour, cycle), pad, digits)
    DayPeriod(by_hour:, midnight:, noon:) -> {
      let on_the_hour =
        { !p.has_minute || m.minute == 0 } && { !p.has_second || m.second == 0 }
      case m.hour, on_the_hour {
        0, True -> midnight
        hour, True if hour == hours_per_half_day -> noon
        hour, _ -> pick_or(by_hour, hour, "")
      }
    }
    Zone(
      names:,
      zero:,
      positive:,
      positive_suffix:,
      positive_whole_suffix:,
      negative:,
      negative_suffix:,
      negative_whole_suffix:,
      pad_hours:,
      separator:,
      optional_minutes:,
    ) ->
      case zone_name(names, m) {
        Ok(name) -> name
        // A fixed zero offset is ICU's GMT zone, which is named from 1970.
        // Before then, and for named zones with no name, ICU writes it like
        // any other offset, such as `GMT+0`.
        Error(Nil) ->
          case
            m.offset_seconds,
            m.unix_seconds >= 0 && m.names == data.Unnamed
          {
            0, True -> zero
            offset, _ -> {
              let #(sign, suffix, whole_suffix) = case offset < 0 {
                True -> #(negative, negative_suffix, negative_whole_suffix)
                False -> #(positive, positive_suffix, positive_whole_suffix)
              }
              let offset = int.absolute_value(offset)
              let hours = number(offset / seconds_per_hour, pad_hours, digits)
              let minutes = offset % seconds_per_hour / seconds_per_minute
              // ICU also writes the extra seconds of old local mean times.
              case minutes, offset % seconds_per_minute, optional_minutes {
                0, 0, True -> sign <> hours <> whole_suffix
                _, 0, _ ->
                  sign
                  <> hours
                  <> separator
                  <> number(minutes, True, digits)
                  <> suffix
                _, seconds, _ ->
                  sign
                  <> hours
                  <> separator
                  <> number(minutes, True, digits)
                  <> separator
                  <> number(seconds, True, digits)
                  <> suffix
              }
            }
          }
      }
    GlueDate | GlueTime -> ""
  }
}

@target(erlang)
/// A named zone's name in the locale, like "BST" or "British Summer Time".
fn zone_name(style: ZoneNameStyle, m: data.Local) -> Result(String, Nil) {
  case style, m.names {
    OnlyOffset, _ | _, data.Unnamed -> Error(Nil)
    ShortNames, data.Named(key:, daylight:, chain:) ->
      zones.name(chain, key, m.unix_seconds, daylight, False)
    LongNames, data.Named(key:, daylight:, chain:) ->
      zones.name(chain, key, m.unix_seconds, daylight, True)
  }
}

@target(erlang)
/// The name at `index`, or `otherwise` as a number if there are too few names.
fn pick(names: Names, index: Int, otherwise: Int, digits: Digits) -> String {
  case index >= 0 && index < tuple_size(names) {
    True -> element(index + 1, names)
    False -> number(otherwise, False, digits)
  }
}

@target(erlang)
fn pick_or(names: Names, index: Int, otherwise: String) -> String {
  case index >= 0 && index < tuple_size(names) {
    True -> element(index + 1, names)
    False -> otherwise
  }
}

// --- Numbers -----------------------------------------------------------------

@target(erlang)
fn hour(hour: Int, cycle: HourCycle) -> Int {
  case cycle {
    H23 -> hour
    H11 -> hour % hours_per_half_day
    H12 ->
      case hour % hours_per_half_day {
        0 -> hours_per_half_day
        h -> h
      }
    H24 ->
      case hour {
        0 -> hours_per_day
        h -> h
      }
  }
}

@target(erlang)
const milliseconds_per_tenth = 100

@target(erlang)
const milliseconds_per_hundredth = 10

@target(erlang)
/// The first `shown` digits of a fraction of a second.
fn fraction(milliseconds: Int, shown: Int, digits: Digits) -> String {
  case shown, milliseconds < milliseconds_per_hundredth {
    1, _ -> number(milliseconds / milliseconds_per_tenth, False, digits)
    2, _ -> number(milliseconds / milliseconds_per_hundredth, True, digits)
    _, True -> number(0, False, digits) <> number(milliseconds, True, digits)
    _, False ->
      number(milliseconds / milliseconds_per_tenth, False, digits)
      <> number(milliseconds % milliseconds_per_tenth, True, digits)
  }
}

@target(erlang)
fn signed(n: Int, minus: String, digits: Digits) -> String {
  case n < 0 {
    True -> minus <> number(-n, False, digits)
    False -> number(n, False, digits)
  }
}

@target(erlang)
/// `n` with zeros in front to make at least `count` digits.
fn padded(n: Int, count: Int, digits: Digits) -> String {
  case count - digit_count(n, 1) {
    missing if missing > 0 ->
      zeros(missing, number(0, False, digits)) <> number(n, False, digits)
    _ -> number(n, False, digits)
  }
}

@target(erlang)
fn digit_count(n: Int, count: Int) -> Int {
  case n < ten {
    True -> count
    False -> digit_count(n / ten, count + 1)
  }
}

@target(erlang)
fn zeros(count: Int, zero: String) -> String {
  case count > 1 {
    True -> zero <> zeros(count - 1, zero)
    False -> zero
  }
}

@target(erlang)
/// A locale's number in the digits table is 0 for ASCII digits.
fn digits_of(number: Int) -> Digits {
  case number {
    0 -> Ascii
    _ -> Local(element(number, digits_table()))
  }
}

@target(erlang)
/// `n` in the locale's digits.
fn number(n: Int, pad: Bool, digits: Digits) -> String {
  case digits, pad && n < ten {
    Ascii, False -> int.to_string(n)
    Ascii, True -> "0" <> int.to_string(n)
    Local(table), False -> local_digits(n, table)
    Local(table), True -> digit(0, table) <> local_digits(n, table)
  }
}

@target(erlang)
fn local_digits(n: Int, table: Names) -> String {
  case n < ten {
    True -> digit(n, table)
    False -> local_digits(n / ten, table) <> digit(n % ten, table)
  }
}

@target(erlang)
fn digit(d: Int, table: Names) -> String {
  pick_or(table, d, int.to_string(d))
}

@target(erlang)
fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

// --- Calendars --------------------------------------------------------------

@target(erlang)
/// A day's era, year, extended year, related year, cycle year, month and day
/// in a calendar, or `[]` if the calendar doesn't cover it. The tests use it.
@internal
pub fn calendar_fields(math: data.Math, epoch_day: Int) -> List(Int) {
  case local(math, epoch_day * seconds_per_day, 0, data.Unnamed) {
    Ok(m) -> [m.era, m.year, m.extended, m.related, m.cycle, m.month, m.day]
    Error(Nil) -> []
  }
}

@target(erlang)
/// The local date and time in the Gregorian calendar, which covers every day.
fn gregorian_local(
  unix_seconds: Int,
  offset_seconds: Int,
  names: data.ZoneNames,
) -> data.Local {
  proleptic_local(
    data.gregorian_newest_era,
    data.gregorian_older_eras,
    data.start_of_time,
    unix_seconds,
    offset_seconds,
    names,
  )
}

@target(erlang)
/// The local date and time in a calendar, or `Error(Nil)` if the calendar
/// doesn't cover that day.
fn local(
  math: data.Math,
  unix_seconds: Int,
  offset_seconds: Int,
  names: data.ZoneNames,
) -> Result(data.Local, Nil) {
  case math {
    data.Proleptic(eras: [newest, ..older], julian_before:) ->
      Ok(proleptic_local(
        newest,
        older,
        julian_before,
        unix_seconds,
        offset_seconds,
        names,
      ))
    data.Table(
      cyclic:,
      first_day:,
      end_day:,
      start_count:,
      starts:,
      layouts:,
      months:,
      years:,
      day_zero:,
    ) -> {
      let #(epoch_day, hour, minute, second) =
        day_and_time(unix_seconds, offset_seconds)
      data.table_local(
        cyclic:,
        first_day:,
        end_day:,
        start_count:,
        starts:,
        layouts:,
        months:,
        years:,
        day_zero:,
        epoch_day:,
        hour:,
        minute:,
        second:,
        offset_seconds:,
        unix_seconds:,
        names:,
      )
    }
    data.Proleptic(eras: [], ..) -> Error(Nil)
  }
}

@target(erlang)
/// The local day since 1970-01-01, and the hour, minute and second.
fn day_and_time(
  unix_seconds: Int,
  offset_seconds: Int,
) -> #(Int, Int, Int, Int) {
  let seconds = unix_seconds + offset_seconds
  let epoch_day = floor_divide(seconds, seconds_per_day)
  let rest = seconds - epoch_day * seconds_per_day
  #(
    epoch_day,
    rest / seconds_per_hour,
    rest % seconds_per_hour / seconds_per_minute,
    rest % seconds_per_minute,
  )
}

@target(erlang)
/// The local date and time in a calendar with Gregorian or Julian months.
fn proleptic_local(
  newest: data.EraRule,
  older: List(data.EraRule),
  julian_before: Int,
  unix_seconds: Int,
  offset_seconds: Int,
  names: data.ZoneNames,
) -> data.Local {
  let #(epoch_day, hour, minute, second) =
    day_and_time(unix_seconds, offset_seconds)
  let #(y, m, d) = case epoch_day < julian_before {
    True -> data.julian_from_days(epoch_day)
    False -> data.civil_from_days(epoch_day)
  }
  // Near the Julian switch a year can start in one calendar and end in
  // the other, so work out its bounds here. Elsewhere `week_year` works
  // them out only when it needs them.
  let #(year_start, next_year_start) = case
    epoch_day < julian_before + days_in_longest_year
  {
    True -> data.year_bounds(y, julian_before)
    False -> #(data.start_of_time, data.start_of_time)
  }
  let data.EraRule(era:, base:, sign:, ..) = era_rule(newest, older, epoch_day)
  data.Local(
    epoch_day:,
    hour:,
    minute:,
    second:,
    offset_seconds:,
    unix_seconds:,
    names:,
    era:,
    year: base + sign * y,
    extended: y,
    related: y,
    cycle: 0,
    month: m - 1,
    day: d,
    year_start:,
    next_year_start:,
  )
}

@target(erlang)
/// The era a day is in. Eras are newest first, and the oldest starts at the
/// start of time.
fn era_rule(
  rule: data.EraRule,
  older: List(data.EraRule),
  epoch_day: Int,
) -> data.EraRule {
  case older, rule.start <= epoch_day {
    [], _ | _, True -> rule
    [next, ..rest], False -> era_rule(next, rest, epoch_day)
  }
}

@target(erlang)
fn floor_divide(n: Int, by: Int) -> Int {
  case int.floor_divide(n, by) {
    Ok(result) -> result
    Error(Nil) -> 0
  }
}
