//// Formats moments with the data `codegen/pack.ts` packs into
//// `glintl_generated_data`. Only used on Erlang.

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
/// A pattern's first byte says which of these it has.
const has_minute_flag = 1

@target(erlang)
const has_second_flag = 2

@target(erlang)
/// Pattern, list and string numbers are this many bytes.
const number_bytes = 2

@target(erlang)
const style_count = 4

@target(erlang)
/// Ops in packed patterns. `glintl_generated_data:ops/0` has the `Op` for
/// each op byte.
type Op {
  /// A byte that isn't an op, which ends the pattern.
  UnknownOp
  LiteralOp
  /// The next token, written with ASCII digits.
  AsciiOp
  YearOp
  /// ICU's week-based year.
  WeekYearOp
  ExtendedYearOp
  RelatedYearOp
  YearNameOp
  MonthNameOp
  DayNameOp
  WeekdayOp
  EraOp
  MonthNumberOp
  DayOp
  MinuteOp
  SecondOp
  HourOp
  DayPeriodOp
  ZoneOp
  GlueDateOp
  GlueTimeOp
}

@target(erlang)
/// In the order of `CYCLES` in `codegen/pack.ts`.
const cycles = [H11, H12, H23, H24]

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
/// Formats are stored by style, in this order.
const styles = [data.Full, data.Long, data.Medium, data.Short]

@target(erlang)
/// A formatter's patterns, ready to render.
pub type Compiled {
  Compiled(
    main: Prepared,
    /// Patterns for eras that ICU formats differently.
    eras: List(#(Int, Prepared)),
    /// A list of digits, or 0 for ASCII digits.
    digits: Int,
    math: Math,
    /// Used for days outside a table calendar's years.
    fallback: Fallback,
  )
}

@target(erlang)
pub type Fallback {
  Fallback(Compiled)
  NoFallback
}

@target(erlang)
/// Tokens to render.
pub opaque type Prepared {
  Prepared(tokens: BitArray, has_minute: Bool, has_second: Bool)
}

// --- Tables ------------------------------------------------------------------

@target(erlang)
@external(erlang, "glintl_generated_data", "ops")
fn ops() -> data.HomogenousUnknownLengthTuple(Op)

@target(erlang)
@external(erlang, "glintl_generated_data", "strings")
fn strings() -> data.HomogenousUnknownLengthTuple(String)

@target(erlang)
@external(erlang, "glintl_generated_data", "lists")
fn lists() -> data.HomogenousUnknownLengthTuple(
  data.HomogenousUnknownLengthTuple(Int),
)

@target(erlang)
@external(erlang, "glintl_generated_data", "patterns")
fn patterns() -> data.HomogenousUnknownLengthTuple(BitArray)

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
fn string(number: Int) -> String {
  element(number, strings())
}

@target(erlang)
/// The name at `index` in a list of names, or `otherwise`.
fn name(list: Int, index: Int, otherwise: String) -> String {
  let names = element(list, lists())
  case index >= 0 && index < tuple_size(names) {
    True -> string(element(index + 1, names))
    False -> otherwise
  }
}

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
  compile_formats(entry, 0, data.gregorian, shown, NoFallback)
}

@target(erlang)
/// A formatter for another calendar, the `position`th in the locale's
/// formats, which falls back to Gregorian outside the calendar's years.
pub fn compile_other(
  locale: Int,
  position: Int,
  math: Math,
  shown: data.Shown,
) -> Compiled {
  let entry = element(locale, locales())
  let gregorian = compile_formats(entry, 0, data.gregorian, shown, NoFallback)
  compile_formats(entry, position, math, shown, Fallback(gregorian))
}

@target(erlang)
/// A locale entry is its digits list, then formats for each calendar.
fn compile_formats(
  entry: BitArray,
  position: Int,
  math: Math,
  shown: data.Shown,
  fallback: Fallback,
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
  Compiled(main:, eras:, digits:, math:, fallback:)
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
      let #(date_tokens, date_flags) = flags(pick(dates, date))
      let #(time_tokens, time_flags) = flags(pick(times, time))
      let #(glue, _) = flags(pick(glues, date))
      let both = int.bitwise_or(date_flags, time_flags)
      Prepared(
        tokens: splice(glue, date_tokens, time_tokens, ops(), <<>>),
        has_minute: has(both, has_minute_flag),
        has_second: has(both, has_second_flag),
      )
    }
    data.DateAndTime(date:, time:), _ -> {
      let index = position(date) * style_count + position(time)
      single(element(number_at(combined, index), patterns()))
    }
  }
}

@target(erlang)
fn single(pattern: BitArray) -> Prepared {
  let #(tokens, flags) = flags(pattern)
  Prepared(
    tokens:,
    has_minute: has(flags, has_minute_flag),
    has_second: has(flags, has_second_flag),
  )
}

@target(erlang)
/// A glue pattern with the date and time tokens put in its place, so each
/// format walks one pattern. Glue patterns only hold text, dates and times.
fn splice(
  glue: BitArray,
  date: BitArray,
  time: BitArray,
  ops: data.HomogenousUnknownLengthTuple(Op),
  acc: BitArray,
) -> BitArray {
  case glue {
    <<code, rest:bits>> ->
      case op_of(ops, code), rest {
        LiteralOp, <<text:16, rest:bits>> ->
          splice(rest, date, time, ops, <<acc:bits, code, text:16>>)
        GlueDateOp, rest ->
          splice(rest, date, time, ops, <<acc:bits, date:bits>>)
        GlueTimeOp, rest ->
          splice(rest, date, time, ops, <<acc:bits, time:bits>>)
        _, _ -> acc
      }
    _ -> acc
  }
}

@target(erlang)
fn flags(pattern: BitArray) -> #(BitArray, Int) {
  case pattern {
    <<flags, tokens:bits>> -> #(tokens, flags)
    _ -> #(<<>>, 0)
  }
}

@target(erlang)
fn has(flags: Int, flag: Int) -> Bool {
  int.bitwise_and(flags, flag) != 0
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

@target(erlang)
fn op_of(ops: data.HomogenousUnknownLengthTuple(Op), code: Int) -> Op {
  case code >= 0 && code < tuple_size(ops) {
    True -> element(code + 1, ops)
    False -> UnknownOp
  }
}

// --- Rendering ---------------------------------------------------------------

@target(erlang)
pub fn render(
  compiled: Compiled,
  unix_seconds: Int,
  offset_minutes: Int,
) -> String {
  let seconds = unix_seconds + offset_minutes * seconds_per_minute
  let epoch_day = floor_divide(seconds, seconds_per_day)
  let rest = seconds - epoch_day * seconds_per_day
  case
    local(compiled.math, epoch_day, rest, offset_minutes, unix_seconds),
    compiled.fallback
  {
    Ok(local), _ -> {
      let prepared = case compiled.eras {
        [] -> compiled.main
        eras ->
          case key_find(eras, local.era) {
            Ok(prepared) -> prepared
            Error(Nil) -> compiled.main
          }
      }
      next(
        prepared.tokens,
        prepared,
        local,
        compiled.digits,
        compiled.digits,
        "",
      )
    }
    Error(Nil), Fallback(gregorian) ->
      render(gregorian, unix_seconds, offset_minutes)
    Error(Nil), NoFallback -> panic as "No calendar covers this day"
  }
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
/// Renders tokens one by one. `d` is the digits for the next token, which
/// are ASCII after an `AsciiOp`. Each op's function starts by reading its
/// bytes and carries on with the rest, so the BEAM reads them in place, and
/// appends to `acc` in place.
fn next(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<code, rest:bits>> ->
      case op_of(ops(), code) {
        LiteralOp -> literal_token(rest, prepared, m, digits, d, acc)
        DayOp -> day_token(rest, prepared, m, digits, d, acc)
        MonthNameOp -> month_name_token(rest, prepared, m, digits, d, acc)
        YearOp -> year_token(rest, prepared, m, digits, d, acc)
        HourOp -> hour_token(rest, prepared, m, digits, d, acc)
        MinuteOp -> minute_token(rest, prepared, m, digits, d, acc)
        MonthNumberOp -> month_number_token(rest, prepared, m, digits, d, acc)
        WeekdayOp -> weekday_token(rest, prepared, m, digits, d, acc)
        SecondOp -> second_token(rest, prepared, m, digits, d, acc)
        DayPeriodOp -> day_period_token(rest, prepared, m, digits, d, acc)
        EraOp -> era_token(rest, prepared, m, digits, d, acc)
        ZoneOp -> zone_token(rest, prepared, m, digits, d, acc)
        WeekYearOp -> week_year_token(rest, prepared, m, digits, d, acc)
        ExtendedYearOp -> extended_year_token(rest, prepared, m, digits, d, acc)
        RelatedYearOp -> related_year_token(rest, prepared, m, digits, d, acc)
        YearNameOp -> year_name_token(rest, prepared, m, digits, d, acc)
        DayNameOp -> day_name_token(rest, prepared, m, digits, d, acc)
        AsciiOp -> next(rest, prepared, m, digits, 0, acc)
        GlueDateOp | GlueTimeOp | UnknownOp -> acc
      }
    _ -> acc
  }
}

@target(erlang)
fn literal_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  _d: Int,
  acc: String,
) -> String {
  case bits {
    <<text:16, rest:bits>> ->
      next(rest, prepared, m, digits, digits, acc <> string(text))
    _ -> acc
  }
}

@target(erlang)
fn day_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<pad, rest:bits>> ->
      next(rest, prepared, m, digits, digits, acc <> number(m.day, pad == 1, d))
    _ -> acc
  }
}

@target(erlang)
fn month_name_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<list:16, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> named(list, m.month, m.month + 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn year_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<1, minus:16, _:16, _:16, rest:bits>> -> {
      let sign = case m.year < 0 {
        True -> string(minus)
        False -> ""
      }
      let year = int.absolute_value(m.year) % two_digit_years
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        { acc <> sign } <> number(year, True, d),
      )
    }
    <<_, minus:16, first:16, minus_first:16, rest:bits>> -> {
      // Year 1 and -1 can have a name, like 元.
      let named = case m.year {
        1 -> string(first)
        -1 -> string(minus_first)
        _ -> ""
      }
      let text = case named {
        "" -> signed(m.year, string(minus), d)
        named -> named
      }
      next(rest, prepared, m, digits, digits, acc <> text)
    }
    _ -> acc
  }
}

@target(erlang)
fn hour_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<pad, cycle, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> number(hour(m.hour, cycle), pad == 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn minute_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<pad, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> number(m.minute, pad == 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn month_number_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<pad, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> number(m.month + 1, pad == 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn weekday_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<list:16, rest:bits>> -> {
      let weekday = modulo(m.epoch_day + thursday, calendar.days_per_week)
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> named(list, weekday, weekday, d),
      )
    }
    _ -> acc
  }
}

@target(erlang)
fn second_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<pad, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> number(m.second, pad == 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn day_period_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  _d: Int,
  acc: String,
) -> String {
  case bits {
    <<by_hour:16, midnight:16, noon:16, rest:bits>> -> {
      let on_the_hour =
        { !prepared.has_minute || m.minute == 0 }
        && { !prepared.has_second || m.second == 0 }
      let text = case m.hour, on_the_hour {
        0, True -> string(midnight)
        hour, True if hour == hours_per_half_day -> string(noon)
        hour, _ -> name(by_hour, hour, "")
      }
      next(rest, prepared, m, digits, digits, acc <> text)
    }
    _ -> acc
  }
}

@target(erlang)
fn era_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<list:16, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> named(list, m.era, m.era, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn zone_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<
      zero:16,
      positive:16,
      positive_suffix:16,
      positive_whole_suffix:16,
      negative:16,
      negative_suffix:16,
      negative_whole_suffix:16,
      pad_hours,
      separator:16,
      optional_minutes,
      rest:bits,
    >> ->
      // ICU only names the zero offset from 1970. Before then it writes it
      // like any other offset, such as `GMT+0`.
      case m.offset_minutes, m.unix_seconds >= 0 {
        0, True -> next(rest, prepared, m, digits, digits, acc <> string(zero))
        offset, _ -> {
          let #(sign, suffix, whole_suffix) = case offset < 0 {
            True -> #(negative, negative_suffix, negative_whole_suffix)
            False -> #(positive, positive_suffix, positive_whole_suffix)
          }
          let offset = int.absolute_value(offset)
          let hours = number(offset / minutes_per_hour, pad_hours == 1, d)
          let text = case offset % minutes_per_hour, optional_minutes {
            0, 1 -> string(sign) <> hours <> string(whole_suffix)
            minutes, _ ->
              string(sign)
              <> hours
              <> string(separator)
              <> number(minutes, True, d)
              <> string(suffix)
          }
          next(rest, prepared, m, digits, digits, acc <> text)
        }
      }
    _ -> acc
  }
}

@target(erlang)
fn week_year_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<minus:16, first_day, minimal_days, count, rest:bits>> -> {
      let #(exceptions, rest) = week_year_exceptions(rest, count)
      let year = calendar.week_year(m, first_day, minimal_days, exceptions)
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> signed(year, string(minus), d),
      )
    }
    _ -> acc
  }
}

@target(erlang)
fn extended_year_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<minus:16, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> signed(m.extended, string(minus), d),
      )
    _ -> acc
  }
}

@target(erlang)
fn related_year_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<rest:bits>> ->
      next(rest, prepared, m, digits, digits, acc <> signed(m.related, "-", d))
  }
}

@target(erlang)
fn year_name_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<list:16, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> named(list, m.cycle, m.cycle + 1, d),
      )
    _ -> acc
  }
}

@target(erlang)
fn day_name_token(
  bits: BitArray,
  prepared: Prepared,
  m: Local,
  digits: Int,
  d: Int,
  acc: String,
) -> String {
  case bits {
    <<list:16, rest:bits>> ->
      next(
        rest,
        prepared,
        m,
        digits,
        digits,
        acc <> named(list, m.day, m.day, d),
      )
    _ -> acc
  }
}

@target(erlang)
/// A name from a list, or `otherwise` as a number if the list is too short.
fn named(list: Int, index: Int, otherwise: Int, digits: Int) -> String {
  let names = element(list, lists())
  case index >= 0 && index < tuple_size(names) {
    True -> string(element(index + 1, names))
    False -> number(otherwise, False, digits)
  }
}

@target(erlang)
/// `#(extended year, first day)` pairs, as 32-bit signed numbers.
fn week_year_exceptions(
  bits: BitArray,
  count: Int,
) -> #(List(#(Int, Int)), BitArray) {
  case count, bits {
    0, _ -> #([], bits)
    _, <<year:32-signed, day:32-signed, rest:bits>> -> {
      let #(others, rest) = week_year_exceptions(rest, count - 1)
      #([#(year, day), ..others], rest)
    }
    _, _ -> #([], <<>>)
  }
}

// --- Numbers -----------------------------------------------------------------

@target(erlang)
fn hour(hour: Int, cycle: Int) -> Int {
  case cycle_of(cycles, cycle) {
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
/// The cycle at `index` in `cycles`, or 0 to 23 if there isn't one.
fn cycle_of(cycles: List(HourCycle), index: Int) -> HourCycle {
  case cycles, index {
    [cycle, ..], 0 -> cycle
    [_, ..rest], _ -> cycle_of(rest, index - 1)
    [], _ -> H23
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
  case digits {
    0 -> int.to_string(d)
    _ -> name(digits, d, int.to_string(d))
  }
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
  case local(math, epoch_day, 0, 0, epoch_day * seconds_per_day) {
    Ok(m) -> [m.era, m.year, m.extended, m.related, m.cycle, m.month, m.day]
    Error(Nil) -> []
  }
}

fn local(
  math: Math,
  epoch_day: Int,
  rest: Int,
  offset_minutes: Int,
  unix_seconds: Int,
) -> Result(Local, Nil) {
  let hour = rest / seconds_per_hour
  let minute = rest % seconds_per_hour / seconds_per_minute
  let second = rest % seconds_per_minute
  case math {
    Proleptic(eras: [newest, ..older], julian_before:) -> {
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
      Ok(Local(
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
      ))
    }
    Table(cyclic:, starts:, shapes:, months:, years:, day_zero:) ->
      calendar.table_local(
        cyclic:,
        starts:,
        shapes:,
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
    Proleptic(eras: [], ..) | NoMath -> Error(Nil)
  }
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
