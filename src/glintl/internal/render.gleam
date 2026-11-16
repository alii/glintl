//// Formats moments on Erlang from the tables `codegen/pack.ts` writes to
//// `glintl_generated_data`. JavaScript uses this module's `Shown` type.
////
//// The tables hold each distinct token once, and a pattern is a list of token
//// numbers, so locales with the same patterns share them.

@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option}
@target(erlang)
import gleam/string
import glintl/internal/data
@target(erlang)
import glintl/internal/matcher
@target(erlang)
import glintl/internal/zones

/// Whether a formatter shows the date, the time or both, and in which styles.
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
const days_in_longest_year = 366

@target(erlang)
const hours_per_half_day = 12

@target(erlang)
const hours_per_day = 24

@target(erlang)
/// 1970-01-01 was a Thursday, and weekdays count from Sunday here.
const thursday = 4

@target(erlang)
/// A two digit year is the year modulo this.
const two_digit_years = 100

@target(erlang)
const ten = 10

@target(erlang)
/// Each pattern number in formats takes this many bytes.
const number_bytes = 2

@target(erlang)
const style_count = 4

@target(erlang)
/// The order formats store their styles in.
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
type Pattern {
  /// `tokens` are 16-bit numbers in the tokens table.
  Pattern(has_minute: Bool, has_second: Bool, tokens: BitArray)
}

@target(erlang)
type Token {
  Literal(String)
  /// Text in a glue pattern. In parts it joins the literals next to it, because
  /// ICU writes the glue, date and time as one pattern.
  GlueText(String)
  /// A part ICU writes with ASCII digits in every locale.
  AsciiDigits(Token)
  /// `first` and `minus_first` name years 1 and -1, like 元. They're `""` when
  /// those years have no name. `min_digits` is the fewest digits a year shows, so
  /// `yyyy` shows year 1 as "0001".
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
  /// The Chinese and Dangi era, which is the 60 year cycle the year is in.
  CycleEra
  YearName(Names)
  /// `numeric` names are numbers in the locale's digits, like "10" for a Hebrew
  /// month.
  MonthName(names: Names, numeric: Bool)
  DayName(names: Names, numeric: Bool)
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
/// The kind of a part. It mirrors the `Part` types in `glintl/date` and
/// `glintl/date_time`, which this module can't import.
pub type PartKind {
  EraPart
  YearPart
  RelatedYearPart
  YearNamePart
  MonthPart
  DayPart
  WeekdayPart
  DayPeriodPart
  HourPart
  MinutePart
  SecondPart
  FractionalSecondPart
  TimeZoneNamePart
  LiteralPart
  UnknownPart
}

@target(erlang)
/// Whether a zone token shows a named zone's name, like ICU's `z` and `zzzz`.
/// Fixed offsets and zones the locale has no name for show the offset.
type ZoneNameStyle {
  OnlyOffset
  ShortNames
  LongNames
  /// Names without standard or summer time, like "PT" or "Pacific Time". These
  /// are ICU's `v` and `vvvv`.
  ShortGenericNames
  LongGenericNames
}

@target(erlang)
pub type Names =
  data.HomogenousUnknownLengthTuple(String)

@target(erlang)
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
type Digits {
  Ascii
  /// The locale's ten digits from zero to nine.
  Local(Names)
  /// Digits from a numbering system other than the locale's default. Text written
  /// in the digits in `own` swaps to these, and years written with `own_minus` use
  /// `minus`. Before `ascii_years_before`, JavaScriptCore writes years in ASCII
  /// digits.
  Swapped(
    digits: Digits,
    own: List(String),
    own_minus: String,
    minus: String,
    ascii_years_before: Option(Int),
  )
}

@target(erlang)
/// How a formatter turns a day into a date.
type Days {
  /// The Gregorian calendar covers every day.
  GregorianDays
  /// Another calendar. Days outside its years use Gregorian. Both are built when
  /// first needed, so a copied formatter stays small.
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
  /// A fields pattern worked out when the formatter is compiled. Each piece has
  /// its run's letter, which is `""` for text.
  Listed(
    has_minute: Bool,
    has_second: Bool,
    pieces: List(#(String, Token)),
    workaround: Workaround,
  )
}

@target(erlang)
/// JavaScriptCore's era workaround. `matcher.EraWorkaround` explains it.
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
/// Reads the 16-bit number at `index`.
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
/// Returns a locale's default hour cycle as its position in `HOUR_CYCLES` in
/// `codegen/patterns.ts`.
pub fn default_hour_cycle(locale: Int) -> Int {
  number_at(element(locale, locales()), 1)
}

@target(erlang)
/// Returns where a locale's default digits are in the digits table.
pub fn default_digits(locale: Int) -> Int {
  number_at(element(locale, locales()), 0)
}

@target(erlang)
/// Returns the name at `index` from 0, or `""` if there's none.
pub fn name_at(names: Names, index: Int) -> String {
  pick_or(names, index, "")
}

@target(erlang)
/// Makes a formatter write numbers with the digits at `number` in the digits
/// table, and its Gregorian fallback too. Years with the locale's default minus
/// sign `own_minus` use `minus` instead, and the calendar's `workaround` says
/// when JavaScriptCore writes years in ASCII.
pub fn with_digits(
  compiled: Compiled,
  number: Int,
  own_minus: String,
  minus: String,
  workaround: matcher.EraWorkaround,
) -> Compiled {
  let days = case compiled.days {
    GregorianDays -> GregorianDays
    OtherDays(math:, gregorian:) ->
      OtherDays(math:, gregorian: fn() {
        with_digits(gregorian(), number, own_minus, minus, workaround)
      })
  }
  let ascii_years_before = case workaround {
    matcher.Replaces(before_ms:, ..) -> option.Some(before_ms)
    _ -> option.None
  }
  let digits = case digits_of(number) {
    digits if digits == compiled.digits -> digits
    digits ->
      Swapped(
        digits:,
        own: digit_list(compiled.digits),
        own_minus:,
        minus:,
        ascii_years_before:,
      )
  }
  Compiled(..compiled, digits:, days:)
}

@target(erlang)
/// Makes a formatter for a locale's Gregorian formats. `cycle` is 0 for the
/// locale's default hour cycle, or else a position in `HOUR_CYCLES` plus 1.
pub fn compile(locale: Int, cycle: Int, shown: Shown) -> Compiled {
  let entry = element(locale, locales())
  compile_formats(entry, 0, cycle, shown, GregorianDays)
}

@target(erlang)
/// Makes a formatter for the calendar at `position` in the locale's formats.
/// Days outside the calendar's years use Gregorian.
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
/// After every calendar's formats, each calendar has one number in `fields`.
const fields_per_calendar = 1

@target(erlang)
/// There are this many fields. Texts hold the append items and display names
/// for each field, the glues for each style, then the decimal separator.
const field_count = 16

@target(erlang)
/// Makes a formatter for fields in the calendar at `position`. Days outside a
/// non-Gregorian calendar's years use Gregorian.
pub fn compile_fields(
  locale: Int,
  position: Int,
  request: matcher.Request,
  calendar: String,
  math: fn() -> data.Math,
  decimal: Option(String),
) -> Compiled {
  let gregorian = fn() {
    compile_fields_at(
      locale,
      0,
      request,
      matcher.NoEraWorkaround,
      GregorianDays,
      decimal,
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
        decimal,
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
  decimal: Option(String),
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
  let own_decimal = at(list.drop(texts, 2 * field_count + style_count), 0, "")
  let m =
    matcher.Matcher(
      entries: entries(element(entries_id, field_entries())),
      append_items: list.take(texts, field_count),
      display_names: list.take(list.drop(texts, field_count), field_count),
      glues: list.take(list.drop(texts, 2 * field_count), style_count),
      default_hour_letter: from_codepoint(hour_letter),
      decimal: option.unwrap(decimal, own_decimal),
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
/// Finds the runs for a letter's field in a fields entry.
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
/// Finds a run's token number. Each run is a letter, a length and flags, then a
/// 16-bit token number.
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
/// Each stored pattern is a skeleton number and a pattern number, then 1 if
/// CLDR gave the skeleton.
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
/// by a pattern for each pair of styles, and 2 by the era's own glues.
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
/// Like `render`, but in parts with Intl's part types.
pub fn render_parts(
  compiled: Compiled,
  unix_seconds: Int,
  milliseconds: Int,
  offset_seconds: Int,
  names: data.ZoneNames,
) -> List(#(PartKind, String)) {
  case compiled.days {
    GregorianDays ->
      write_parts(
        compiled,
        gregorian_local(unix_seconds, offset_seconds, names),
        milliseconds,
      )
    OtherDays(math:, gregorian:) ->
      case local(math(), unix_seconds, offset_seconds, names) {
        Ok(local) -> write_parts(compiled, local, milliseconds)
        Error(Nil) ->
          render_parts(
            gregorian(),
            unix_seconds,
            milliseconds,
            offset_seconds,
            names,
          )
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
fn write_parts(
  compiled: Compiled,
  local: data.Local,
  milliseconds: Int,
) -> List(#(PartKind, String)) {
  let prepared = case compiled.eras {
    [] -> compiled.main
    eras ->
      case key_find(eras, local.era) {
        Ok(prepared) -> prepared
        Error(Nil) -> compiled.main
      }
  }
  let reversed = case prepared {
    Prepared(tokens:, ..) ->
      walk_parts(
        tokens,
        prepared,
        local,
        milliseconds,
        compiled.digits,
        [],
        False,
      )
    Listed(..) -> {
      let #(pieces, added) =
        listed_pieces(prepared, local, milliseconds, compiled.digits)
      // JavaScriptCore keeps the parts its workaround adds on their own.
      list.fold(pieces, [], fn(acc, piece) { add_part(acc, piece.1, piece.2) })
      |> list.append(list.reverse(added), _)
    }
  }
  list.reverse(reversed)
}

@target(erlang)
/// Adds a part to parts in reverse order. Like Intl, it leaves out empty parts
/// and joins literals that come together.
fn add_part(
  parts: List(#(PartKind, String)),
  kind: PartKind,
  text: String,
) -> List(#(PartKind, String)) {
  case text, kind, parts {
    "", _, _ -> parts
    _, LiteralPart, [#(LiteralPart, before), ..rest] -> [
      #(LiteralPart, before <> text),
      ..rest
    ]
    _, _, _ -> [#(kind, text), ..parts]
  }
}

@target(erlang)
/// Returns a fields pattern's pieces with their run letter, kind and text after
/// JavaScriptCore's era workaround, then the parts the workaround adds to the
/// end.
fn listed_pieces(
  prepared: Prepared,
  local: data.Local,
  milliseconds: Int,
  digits: Digits,
) -> #(List(#(String, PartKind, String)), List(#(PartKind, String))) {
  case prepared {
    Listed(pieces:, workaround:, ..) ->
      list.map(pieces, fn(piece) {
        #(
          piece.0,
          kind(piece.1),
          text(piece.1, prepared, local, milliseconds, digits),
        )
      })
      |> with_workaround_parts(workaround, local, milliseconds)
    Prepared(..) -> #([], [])
  }
}

@target(erlang)
const milliseconds_per_second = 1000

@target(erlang)
/// Applies JavaScriptCore's era workaround to the text of each piece.
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
/// Like `with_workaround`, for parts. It also returns the parts the workaround
/// adds to the end.
fn with_workaround_parts(
  pieces: List(#(String, PartKind, String)),
  workaround: Workaround,
  m: data.Local,
  milliseconds: Int,
) -> #(List(#(String, PartKind, String)), List(#(PartKind, String))) {
  let ms = m.unix_seconds * milliseconds_per_second + milliseconds
  case workaround {
    ReplaceEra(before_ms:, text:, two_digit_year:) if ms < before_ms -> {
      let era = last_part_index(pieces, "G", 0, -1)
      let year = last_part_index(pieces, "y", 0, -1)
      let replaced =
        list.index_map(pieces, fn(piece, i) {
          case i == era, i == year {
            True, _ -> #(piece.0, piece.1, text)
            _, True -> #(
              piece.0,
              piece.1,
              flipped_year(m.extended, two_digit_year),
            )
            _, _ -> piece
          }
        })
      #(replaced, [])
    }
    AppendEra(before_ms:, text:) if ms < before_ms -> {
      let kept = list.filter(pieces, fn(piece) { piece.0 != "G" })
      let written = string_concat(list.map(kept, fn(piece) { piece.2 }))
      case matcher.ends_with_space(written) {
        True -> #(kept, [#(EraPart, text)])
        False -> #(kept, [#(LiteralPart, " "), #(EraPart, text)])
      }
    }
    _ -> #(pieces, [])
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
fn last_part_index(
  pieces: List(#(String, PartKind, String)),
  letter: String,
  i: Int,
  found: Int,
) -> Int {
  case pieces {
    [] -> found
    [#(l, _, _), ..rest] if l == letter ->
      last_part_index(rest, letter, i + 1, i)
    [_, ..rest] -> last_part_index(rest, letter, i + 1, found)
  }
}

@target(erlang)
/// JavaScriptCore writes 1 minus ICU's year in ASCII digits.
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
/// Like `walk`, but adds parts in reverse order. Literals stay apart the way
/// Intl gave them to the generator, except that glue text joins the literals
/// next to it. `join` says the last part was glue text.
fn walk_parts(
  bits: BitArray,
  p: Prepared,
  m: data.Local,
  milliseconds: Int,
  digits: Digits,
  acc: List(#(PartKind, String)),
  join: Bool,
) -> List(#(PartKind, String)) {
  case bits {
    <<id:16, rest:bits>> ->
      case element(id, tokens()), p {
        GlueDate, Prepared(date:, ..) ->
          walk_parts(date, p, m, milliseconds, digits, acc, join)
          |> walk_parts(rest, p, m, milliseconds, digits, _, False)
        GlueTime, Prepared(time:, ..) ->
          walk_parts(time, p, m, milliseconds, digits, acc, join)
          |> walk_parts(rest, p, m, milliseconds, digits, _, False)
        GlueText(""), _ ->
          walk_parts(rest, p, m, milliseconds, digits, acc, join)
        GlueText(text), _ ->
          add_part(acc, LiteralPart, text)
          |> walk_parts(rest, p, m, milliseconds, digits, _, True)
        token, _ ->
          case text(token, p, m, milliseconds, digits), join {
            "", _ -> walk_parts(rest, p, m, milliseconds, digits, acc, join)
            text, True ->
              add_part(acc, kind(token), text)
              |> walk_parts(rest, p, m, milliseconds, digits, _, False)
            text, False ->
              [#(kind(token), text), ..acc]
              |> walk_parts(rest, p, m, milliseconds, digits, _, False)
          }
      }
    _ -> acc
  }
}

@target(erlang)
/// Returns the kind of part a token writes.
fn kind(token: Token) -> PartKind {
  case token {
    Literal(_) | GlueText(_) | GlueDate | GlueTime -> LiteralPart
    AsciiDigits(inner) -> kind(inner)
    Year(..) | ExtendedYear(..) -> YearPart
    WeekYear(..) -> UnknownPart
    RelatedYear(..) -> RelatedYearPart
    CycleEra | Era(_) -> EraPart
    YearName(_) -> YearNamePart
    MonthName(..) | MonthNumber(..) -> MonthPart
    DayName(..) | Day(..) -> DayPart
    Weekday(_) -> WeekdayPart
    DayPeriod(..) -> DayPeriodPart
    Hour(..) -> HourPart
    Minute(..) -> MinutePart
    Second(..) -> SecondPart
    Fraction(..) -> FractionalSecondPart
    Zone(..) -> TimeZoneNamePart
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
    Literal(text) | GlueText(text) -> text
    AsciiDigits(inner) -> text(inner, p, m, milliseconds, Ascii)
    Year(two_digit: True, minus:, ..) -> {
      let #(minus, digits) = case digits {
        Swapped(..) -> year_digits(minus, digits, p, m, milliseconds)
        _ -> #(minus, digits)
      }
      let sign = case m.year < 0 {
        True -> minus
        False -> ""
      }
      sign <> number(int.absolute_value(m.year) % two_digit_years, True, digits)
    }
    Year(two_digit: False, min_digits:, minus:, first:, minus_first:) -> {
      let #(minus, digits) = case digits, first {
        // ICU's `jpanyear` rules name year 1 and write other years in ASCII.
        Swapped(..), "" -> year_digits(minus, digits, p, m, milliseconds)
        Swapped(..), _ -> #(minus, Ascii)
        _, _ -> #(minus, digits)
      }
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
      let #(minus, digits) = case digits {
        Swapped(..) -> year_digits(minus, digits, p, m, milliseconds)
        _ -> #(minus, digits)
      }
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
    ExtendedYear(minus:, two_digit: False) -> {
      let #(minus, digits) = case digits {
        Swapped(..) -> year_digits(minus, digits, p, m, milliseconds)
        _ -> #(minus, digits)
      }
      signed(m.extended, minus, digits)
    }
    ExtendedYear(minus:, two_digit: True) -> {
      let #(minus, digits) = case digits {
        Swapped(..) -> year_digits(minus, digits, p, m, milliseconds)
        _ -> #(minus, digits)
      }
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
    MonthName(names:, numeric: False) ->
      pick(names, m.month, m.month + 1, digits)
    MonthName(names:, numeric: True) ->
      pick(names, m.month, m.month + 1, digits) |> swapped(True, digits)
    DayName(names:, numeric: False) -> pick(names, m.day, m.day, digits)
    DayName(names:, numeric: True) ->
      pick(names, m.day, m.day, digits) |> swapped(True, digits)
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
            0, True -> swapped(zero, True, digits)
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
/// Returns a named zone's name in the locale.
fn zone_name(style: ZoneNameStyle, m: data.Local) -> Result(String, Nil) {
  case style, m.names {
    OnlyOffset, _ | _, data.Unnamed -> Error(Nil)
    ShortNames, data.Named(key:, daylight:, chain:, ..) ->
      zones.name(chain, key, m.unix_seconds, daylight, False)
    LongNames, data.Named(key:, daylight:, chain:, ..) ->
      zones.name(chain, key, m.unix_seconds, daylight, True)
    ShortGenericNames, data.Named(key:, zone:, chain:, location:, ..) ->
      zones.generic_name(chain, location, key, zone, m.unix_seconds, False)
    LongGenericNames, data.Named(key:, zone:, chain:, location:, ..) ->
      zones.generic_name(chain, location, key, zone, m.unix_seconds, True)
  }
}

@target(erlang)
/// Returns the name at `index`, or `otherwise` as a number if there are too few
/// names.
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
/// Writes the first `shown` digits of a fraction of a second.
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
/// Writes `n` with zeros in front to make at least `count` digits.
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
const digit_count_in_table = 10

@target(erlang)
/// Number 0 in the digits table means ASCII. `Local` always has all ten
/// digits, so `digit` can read them without checking.
fn digits_of(number: Int) -> Digits {
  case number {
    0 -> Ascii
    _ -> {
      let table = element(number, digits_table())
      case tuple_size(table) == digit_count_in_table {
        True -> Local(table)
        False -> Ascii
      }
    }
  }
}

@target(erlang)
/// Writes `n` in the locale's digits.
fn number(n: Int, pad: Bool, digits: Digits) -> String {
  case digits, pad && n < ten {
    Ascii, False -> int.to_string(n)
    Ascii, True -> "0" <> int.to_string(n)
    Local(table), False -> local_digits(n, table)
    Local(table), True -> digit(0, table) <> local_digits(n, table)
    Swapped(digits:, ..), _ -> number(n, pad, digits)
  }
}

@target(erlang)
/// Swaps text from the locale's default digits to the numbering system's when
/// `swap` is true.
fn swapped(text: String, swap: Bool, digits: Digits) -> String {
  case swap, digits {
    True, Swapped(digits:, own:, ..) ->
      string.to_graphemes(text)
      |> list.map(fn(c) {
        case index_of(own, c, 0) {
          i if i < digit_count_in_table -> number(i, False, digits)
          _ -> c
        }
      })
      |> string_concat
    _, _ -> text
  }
}

@target(erlang)
/// Returns a year's minus sign and digits in the numbering system that's set.
fn year_digits(
  minus: String,
  digits: Digits,
  p: Prepared,
  m: data.Local,
  milliseconds: Int,
) -> #(String, Digits) {
  let ms = m.unix_seconds * milliseconds_per_second + milliseconds
  case digits {
    // JavaScriptCore flips years only in patterns with an era.
    Swapped(ascii_years_before: option.Some(before), ..) if ms < before ->
      case has_era(p) {
        True -> #(minus, Ascii)
        False -> swapped_minus(minus, digits)
      }
    _ -> swapped_minus(minus, digits)
  }
}

@target(erlang)
fn swapped_minus(minus: String, digits: Digits) -> #(String, Digits) {
  case digits {
    Swapped(own_minus:, minus: swapped, ..) if minus == own_minus -> #(
      swapped,
      digits,
    )
    _ -> #(minus, digits)
  }
}

@target(erlang)
fn has_era(p: Prepared) -> Bool {
  case p {
    Listed(pieces:, ..) -> list.any(pieces, fn(piece) { is_era(piece.1) })
    Prepared(tokens:, date:, time:, ..) ->
      ids_have_era(tokens) || ids_have_era(date) || ids_have_era(time)
  }
}

@target(erlang)
fn ids_have_era(ids: BitArray) -> Bool {
  case ids {
    <<id:16, rest:bits>> -> is_era(element(id, tokens())) || ids_have_era(rest)
    _ -> False
  }
}

@target(erlang)
fn is_era(token: Token) -> Bool {
  case token {
    Era(_) -> True
    AsciiDigits(inner) -> is_era(inner)
    _ -> False
  }
}

@target(erlang)
fn digit_list(digits: Digits) -> List(String) {
  int.range(from: digit_count_in_table - 1, to: -1, with: [], run: fn(acc, d) {
    [number(d, False, digits), ..acc]
  })
}

@target(erlang)
fn local_digits(n: Int, table: Names) -> String {
  case n >= 0, n < ten {
    True, True -> digit(n, table)
    True, False -> local_digits(n / ten, table) <> digit(n % ten, table)
    // Callers write the sign themselves, so this is only a safety net.
    False, _ -> int.to_string(n)
  }
}

@target(erlang)
fn digit(d: Int, table: Names) -> String {
  element(d + 1, table)
}

@target(erlang)
fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

// --- Calendars --------------------------------------------------------------

@target(erlang)
/// Returns a day's era, year, extended year, related year, cycle year, month
/// and day in a calendar, or `[]` if the calendar doesn't cover it. The tests
/// use this.
@internal
pub fn calendar_fields(math: data.Math, epoch_day: Int) -> List(Int) {
  case local(math, epoch_day * seconds_per_day, 0, data.Unnamed) {
    Ok(m) -> [m.era, m.year, m.extended, m.related, m.cycle, m.month, m.day]
    Error(Nil) -> []
  }
}

@target(erlang)
/// Returns the local date and time in the Gregorian calendar. It covers every
/// day, so this can't fail.
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
/// Returns the local date and time in a calendar, or `Error(Nil)` for a day the
/// calendar doesn't cover.
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
/// Returns the local day since 1970-01-01 with the hour, minute and second.
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
/// Returns the local date and time in a calendar with Gregorian or Julian
/// months.
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
/// Finds the era a day is in. Eras are newest first, and the oldest starts at
/// the start of time.
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
