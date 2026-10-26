//// Formats moments with the tables `codegen/pack.ts` writes to
//// `glintl_generated_data`. Only used on Erlang.
////
//// Each distinct token is stored once, and a pattern is its tokens' numbers.
//// A formatter only points at these literals, so nothing is copied.

import gleam/int
import glintl/internal/calendar
import glintl/internal/data.{
  type EraRule, type Local, type Math, EraRule, Local, NoMath, Proleptic, Table,
}

pub const seconds_per_minute = 60

const seconds_per_hour = 3600

pub const seconds_per_day = 86_400

/// The longest a year can be in a calendar with Gregorian months.
const days_in_longest_year = 366

@target(erlang)
const minutes_per_hour = 60

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
/// A pattern, as `codegen/pack.ts` writes it.
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
  Year(two_digit: Bool, minus: String, first: String, minus_first: String)
  /// ICU's week-based year.
  WeekYear(
    minus: String,
    first_day: Int,
    minimal_days: Int,
    exceptions: List(#(Int, Int)),
  )
  ExtendedYear(minus: String)
  RelatedYear
  YearName(Names)
  MonthName(Names)
  DayName(Names)
  Weekday(Names)
  Era(Names)
  MonthNumber(pad: Bool)
  Day(pad: Bool)
  Minute(pad: Bool)
  Second(pad: Bool)
  Hour(pad: Bool, cycle: HourCycle)
  DayPeriod(by_hour: Names, midnight: String, noon: String)
  Zone(
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
type Names =
  data.HomogenousUnknownLengthTuple(String)

@target(erlang)
/// A formatter's patterns, ready to render.
pub opaque type Compiled {
  Compiled(
    main: Prepared,
    /// Patterns for eras that ICU formats differently.
    eras: List(#(Int, Prepared)),
    /// The locale's number in the digits table, or 0 for ASCII digits.
    digits: Int,
    days: Days,
  )
}

@target(erlang)
/// How a formatter turns a day into a date.
type Days {
  /// Gregorian covers every day.
  GregorianDays
  /// Another calendar, and Gregorian for days outside its years. Both are
  /// built when needed, so a copied formatter stays small.
  OtherDays(math: fn() -> Math, gregorian: fn() -> Compiled)
}

@target(erlang)
/// Tokens to render. In a glue pattern, `date` and `time` are what it joins.
type Prepared {
  Prepared(
    tokens: BitArray,
    date: BitArray,
    time: BitArray,
    has_minute: Bool,
    has_second: Bool,
  )
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
/// A formatter for a locale's Gregorian formats.
pub fn compile(locale: Int, shown: data.Shown) -> Compiled {
  let entry = element(locale, locales())
  compile_formats(entry, 0, shown, GregorianDays)
}

@target(erlang)
/// A formatter for another calendar, the `position`th in the locale's
/// formats, which falls back to Gregorian outside the calendar's years.
pub fn compile_other(
  locale: Int,
  position: Int,
  math: fn() -> Math,
  shown: data.Shown,
) -> Compiled {
  let entry = element(locale, locales())
  let gregorian = fn() { compile_formats(entry, 0, shown, GregorianDays) }
  compile_formats(entry, position, shown, OtherDays(math:, gregorian:))
}

@target(erlang)
/// A locale entry is its digits number, then formats for each calendar.
fn compile_formats(
  entry: BitArray,
  position: Int,
  shown: data.Shown,
  days: Days,
) -> Compiled {
  let digits = number_at(entry, 0)
  let formats = element(number_at(entry, position + 1), formats())
  let #(dates, formats) = split(formats)
  let #(times, formats) = split(formats)
  let #(glues, formats) = split(formats)
  let main = prepare(dates, times, glues, <<>>, shown)
  let eras = case shown, formats {
    data.TimeOnly(_), _ -> []
    _, <<count, eras:bits>> -> eras_of(eras, count, times, glues, shown)
    _, _ -> []
  }
  Compiled(main:, eras:, digits:, days:)
}

@target(erlang)
/// Splits off a pattern number for each style.
fn split(bits: BitArray) -> #(BitArray, BitArray) {
  case bits {
    <<each:bytes-size(style_count * number_bytes), rest:bits>> -> #(each, rest)
    _ -> #(<<>>, <<>>)
  }
}

@target(erlang)
/// Each era is its number, its dates, then a flag and, if set, a pattern for
/// each date style and time style.
fn eras_of(
  bits: BitArray,
  count: Int,
  times: BitArray,
  glues: BitArray,
  shown: data.Shown,
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
    _, <<era, dates:bytes-size(each), _, rest:bits>> -> [
      #(era, prepare(dates, times, glues, <<>>, shown)),
      ..eras_of(rest, count - 1, times, glues, shown)
    ]
    _, _ -> []
  }
}

@target(erlang)
/// `combined` holds a pattern for each date and time style, when ICU doesn't
/// just glue them together.
fn prepare(
  dates: BitArray,
  times: BitArray,
  glues: BitArray,
  combined: BitArray,
  shown: data.Shown,
) -> Prepared {
  let pick = fn(bits, style) {
    element(number_at(bits, position(style)), patterns())
  }
  case shown, combined {
    data.TimeOnly(time), _ -> single(pick(times, time))
    data.DateOnly(date), _ -> single(pick(dates, date))
    data.DateAndTime(date:, time:), <<>> -> {
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
    data.DateAndTime(date:, time:), _ -> {
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
  offset_minutes: Int,
) -> String {
  case compiled.days {
    GregorianDays ->
      write(compiled, gregorian_local(unix_seconds, offset_minutes))
    OtherDays(math:, gregorian:) ->
      case local(math(), unix_seconds, offset_minutes) {
        Ok(local) -> write(compiled, local)
        Error(Nil) -> render(gregorian(), unix_seconds, offset_minutes)
      }
  }
}

@target(erlang)
fn write(compiled: Compiled, local: Local) -> String {
  let prepared = case compiled.eras {
    [] -> compiled.main
    eras ->
      case key_find(eras, local.era) {
        Ok(prepared) -> prepared
        Error(Nil) -> compiled.main
      }
  }
  walk(prepared.tokens, prepared, local, compiled.digits, "")
}

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
  prepared: Prepared,
  m: Local,
  digits: Int,
  acc: String,
) -> String {
  case bits {
    <<id:16, rest:bits>> ->
      case element(id, tokens()) {
        GlueDate ->
          walk(
            rest,
            prepared,
            m,
            digits,
            walk(prepared.date, prepared, m, digits, acc),
          )
        GlueTime ->
          walk(
            rest,
            prepared,
            m,
            digits,
            walk(prepared.time, prepared, m, digits, acc),
          )
        token ->
          walk(
            rest,
            prepared,
            m,
            digits,
            acc <> text(token, prepared, m, digits),
          )
      }
    _ -> acc
  }
}

@target(erlang)
fn text(token: Token, prepared: Prepared, m: Local, digits: Int) -> String {
  case token {
    Literal(text) -> text
    AsciiDigits(inner) -> text(inner, prepared, m, 0)
    Year(two_digit: True, minus:, ..) -> {
      let sign = case m.year < 0 {
        True -> minus
        False -> ""
      }
      sign <> number(int.absolute_value(m.year) % two_digit_years, True, digits)
    }
    Year(two_digit: False, minus:, first:, minus_first:) -> {
      // Year 1 and -1 can have a name, like 元.
      let named = case m.year {
        1 -> first
        -1 -> minus_first
        _ -> ""
      }
      case named {
        "" -> signed(m.year, minus, digits)
        named -> named
      }
    }
    WeekYear(minus:, first_day:, minimal_days:, exceptions:) ->
      signed(
        calendar.week_year(m, first_day, minimal_days, exceptions),
        minus,
        digits,
      )
    ExtendedYear(minus:) -> signed(m.extended, minus, digits)
    RelatedYear -> signed(m.related, "-", digits)
    YearName(names) -> pick(names, m.cycle, m.cycle + 1, digits)
    MonthName(names) -> pick(names, m.month, m.month + 1, digits)
    DayName(names) -> pick(names, m.day, m.day, digits)
    Weekday(names) -> {
      let weekday = modulo(m.epoch_day + thursday, calendar.days_per_week)
      pick(names, weekday, weekday, digits)
    }
    Era(names) -> pick(names, m.era, m.era, digits)
    MonthNumber(pad:) -> number(m.month + 1, pad, digits)
    Day(pad:) -> number(m.day, pad, digits)
    Minute(pad:) -> number(m.minute, pad, digits)
    Second(pad:) -> number(m.second, pad, digits)
    Hour(pad:, cycle:) -> number(hour(m.hour, cycle), pad, digits)
    DayPeriod(by_hour:, midnight:, noon:) -> {
      let on_the_hour =
        { !prepared.has_minute || m.minute == 0 }
        && { !prepared.has_second || m.second == 0 }
      case m.hour, on_the_hour {
        0, True -> midnight
        hour, True if hour == hours_per_half_day -> noon
        hour, _ -> pick_or(by_hour, hour, "")
      }
    }
    Zone(
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
      // ICU only names the zero offset from 1970. Before then it writes it
      // like any other offset, such as `GMT+0`.
      case m.offset_minutes, m.unix_seconds >= 0 {
        0, True -> zero
        offset, _ -> {
          let #(sign, suffix, whole_suffix) = case offset < 0 {
            True -> #(negative, negative_suffix, negative_whole_suffix)
            False -> #(positive, positive_suffix, positive_whole_suffix)
          }
          let offset = int.absolute_value(offset)
          let hours = number(offset / minutes_per_hour, pad_hours, digits)
          case offset % minutes_per_hour, optional_minutes {
            0, True -> sign <> hours <> whole_suffix
            minutes, _ ->
              sign
              <> hours
              <> separator
              <> number(minutes, True, digits)
              <> suffix
          }
        }
      }
    GlueDate | GlueTime -> ""
  }
}

@target(erlang)
/// A name from a token, or `otherwise` as a number if there are too few.
fn pick(names: Names, index: Int, otherwise: Int, digits: Int) -> String {
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
fn signed(n: Int, minus: String, digits: Int) -> String {
  case n < 0 {
    True -> minus <> number(-n, False, digits)
    False -> number(n, False, digits)
  }
}

@target(erlang)
/// `n` in the locale's digits, or ASCII digits if `digits` is 0.
fn number(n: Int, pad: Bool, digits: Int) -> String {
  case digits, pad && n < ten {
    0, False -> int.to_string(n)
    0, True -> "0" <> int.to_string(n)
    _, False -> local_digits(n, digits)
    _, True -> digit(0, digits) <> local_digits(n, digits)
  }
}

@target(erlang)
fn local_digits(n: Int, digits: Int) -> String {
  case n < ten {
    True -> digit(n, digits)
    False -> local_digits(n / ten, digits) <> digit(n % ten, digits)
  }
}

@target(erlang)
fn digit(d: Int, digits: Int) -> String {
  pick_or(element(digits, digits_table()), d, int.to_string(d))
}

@target(erlang)
fn modulo(n: Int, by: Int) -> Int {
  { n % by + by } % by
}

// --- Calendars --------------------------------------------------------------

/// A day's era, year, extended year, related year, cycle year, month and day
/// in a calendar, or `[]` if the calendar doesn't cover it. For tests.
@internal
pub fn calendar_fields(math: Math, epoch_day: Int) -> List(Int) {
  case local(math, epoch_day * seconds_per_day, 0) {
    Ok(m) -> [m.era, m.year, m.extended, m.related, m.cycle, m.month, m.day]
    Error(Nil) -> []
  }
}

@target(erlang)
/// A moment in a Gregorian calendar, which covers every day.
fn gregorian_local(unix_seconds: Int, offset_minutes: Int) -> Local {
  proleptic_local(
    data.gregorian_newest_era,
    data.gregorian_older_eras,
    data.start_of_time,
    unix_seconds,
    offset_minutes,
  )
}

/// A moment in a calendar, or `Error(Nil)` if the calendar doesn't cover it.
fn local(
  math: Math,
  unix_seconds: Int,
  offset_minutes: Int,
) -> Result(Local, Nil) {
  case math {
    Proleptic(eras: [newest, ..older], julian_before:) ->
      Ok(proleptic_local(
        newest,
        older,
        julian_before,
        unix_seconds,
        offset_minutes,
      ))
    Table(
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
        day_and_time(unix_seconds, offset_minutes)
      calendar.table_local(
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
        offset_minutes:,
        unix_seconds:,
      )
    }
    Proleptic(eras: [], ..) | NoMath -> Error(Nil)
  }
}

/// The local day since 1970-01-01, and the hour, minute and second.
fn day_and_time(
  unix_seconds: Int,
  offset_minutes: Int,
) -> #(Int, Int, Int, Int) {
  let seconds = unix_seconds + offset_minutes * seconds_per_minute
  let epoch_day = floor_divide(seconds, seconds_per_day)
  let rest = seconds - epoch_day * seconds_per_day
  #(
    epoch_day,
    rest / seconds_per_hour,
    rest % seconds_per_hour / seconds_per_minute,
    rest % seconds_per_minute,
  )
}

/// A moment in a calendar with Gregorian or Julian months.
fn proleptic_local(
  newest: EraRule,
  older: List(EraRule),
  julian_before: Int,
  unix_seconds: Int,
  offset_minutes: Int,
) -> Local {
  let #(epoch_day, hour, minute, second) =
    day_and_time(unix_seconds, offset_minutes)
  let #(y, m, d) = case epoch_day < julian_before {
    True -> calendar.julian_from_days(epoch_day)
    False -> civil_from_days(epoch_day)
  }
  // Near the Julian switch a year can start in one calendar and end in
  // the other, so its bounds are worked out here. Elsewhere `week_year`
  // works them out only if needed.
  let #(year_start, next_year_start) = case
    epoch_day < julian_before + days_in_longest_year
  {
    True -> calendar.year_bounds(y, julian_before)
    False -> #(data.start_of_time, data.start_of_time)
  }
  let EraRule(era:, base:, sign:, ..) = era_rule(newest, older, epoch_day)
  Local(
    epoch_day:,
    hour:,
    minute:,
    second:,
    offset_minutes:,
    unix_seconds:,
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

/// The era a day is in. Eras are newest first, and the oldest starts at the
/// start of time.
fn era_rule(rule: EraRule, older: List(EraRule), epoch_day: Int) -> EraRule {
  case older, rule.start <= epoch_day {
    [], _ | _, True -> rule
    [next, ..rest], False -> era_rule(next, rest, epoch_day)
  }
}

/// Days since 1970-01-01 to a proleptic Gregorian date. From Howard Hinnant's
/// `civil_from_days`, whose other numbers are part of the published
/// algorithm: <https://howardhinnant.github.io/date_algorithms.html>.
fn civil_from_days(days: Int) -> #(Int, Int, Int) {
  let z = days + calendar.days_from_march_of_year_zero
  let era = floor_divide(z, calendar.days_per_400_years)
  let doe = z - era * calendar.days_per_400_years
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day = doy - { 153 * mp + 2 } / 5 + 1
  let month = case mp < 10 {
    True -> mp + 3
    False -> mp - 9
  }
  let year = yoe + era * 400
  let year = case month <= 2 {
    True -> year + 1
    False -> year
  }
  #(year, month, day)
}

fn floor_divide(n: Int, by: Int) -> Int {
  case int.floor_divide(n, by) {
    Ok(result) -> result
    Error(Nil) -> 0
  }
}
