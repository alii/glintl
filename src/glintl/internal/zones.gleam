//// Finds a named time zone's offset and name at a moment on Erlang, the same
//// way as ICU's `OlsonTimeZone` and `TimeZoneNames`. `codegen/zones.ts` writes
//// the data.

@target(erlang)
import glintl/internal/data

@target(erlang)
/// When a zone's offset changes, and what it changes to.
pub type Rules {
  Rules(
    /// Seconds since 1970, 64 bits each.
    transitions: BitArray,
    /// Standard and daylight saving seconds, 32 bits each. The first applies
    /// before any transition.
    types: BitArray,
    /// The type after each transition, a byte each.
    type_map: BitArray,
    final: Final,
  )
}

@target(erlang)
/// The yearly rule after the last transition, from ICU's `finalRule`.
pub type Final {
  NoFinal
  /// `rule` is ICU's eleven numbers for a `SimpleTimeZone`, in seconds.
  Final(raw: Int, year: Int, rule: Rule)
}

/// ICU's eleven numbers for a yearly summer time rule, in seconds.
pub type Rule =
  #(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)

@target(erlang)
type Table

@target(erlang)
/// From a lowercase name: the name as ICU writes it, its zone's number, and
/// its key in the names data.
@external(erlang, "glintl_generated_time_zones", "zone")
pub fn find(lowercase_name: String) -> Result(#(String, Int, Int), Nil)

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "rules")
fn table() -> Table

@target(erlang)
@external(erlang, "erlang", "element")
fn element(position: Int, table: Table) -> Rules

@target(erlang)
const transition_bits = 64

@target(erlang)
const type_bits = 64

@target(erlang)
const bits_per_byte = 8

@target(erlang)
const offset_bits = 32

@target(erlang)
const seconds_per_day = 86_400

@target(erlang)
const days_per_week = 7

@target(erlang)
/// How many seconds the zone is ahead of UTC at a moment, and whether it's on
/// summer time.
pub fn offset(zone: Int, unix_seconds: Int) -> #(Int, Bool) {
  let Rules(transitions:, types:, type_map:, final:) =
    element(zone + 1, table())
  case final {
    Final(raw:, year:, rule:) ->
      case unix_seconds >= data.days_from_civil(year, 1, 1) * seconds_per_day {
        True -> final_offset(raw, rule, unix_seconds)
        False -> historical(transitions, types, type_map, unix_seconds)
      }
    NoFinal -> historical(transitions, types, type_map, unix_seconds)
  }
}

// --- Before the final rule ---------------------------------------------------

@target(erlang)
fn historical(
  transitions: BitArray,
  types: BitArray,
  type_map: BitArray,
  unix_seconds: Int,
) -> #(Int, Bool) {
  let count = bit_array_bytes(transitions) * bits_per_byte / transition_bits
  let type_ = case last_at_or_before(transitions, unix_seconds, 0, count) {
    -1 -> 0
    i -> byte(type_map, i)
  }
  let assert <<
    _:bits-size(type_ * type_bits),
    raw:signed-size(offset_bits),
    dst:signed-size(offset_bits),
    _:bits,
  >> = types
  #(raw + dst, dst != 0)
}

@target(erlang)
/// The last transition at or before `seconds`, or -1 if there's none. It
/// searches from `low` up to `high`, leaving out `high`.
fn last_at_or_before(
  transitions: BitArray,
  seconds: Int,
  low: Int,
  high: Int,
) -> Int {
  case low >= high {
    True -> low - 1
    False -> {
      let middle = { low + high } / 2
      case transition(transitions, middle) <= seconds {
        True -> last_at_or_before(transitions, seconds, middle + 1, high)
        False -> last_at_or_before(transitions, seconds, low, middle)
      }
    }
  }
}

@target(erlang)
fn transition(transitions: BitArray, i: Int) -> Int {
  let assert <<
    _:bits-size(i * transition_bits),
    t:signed-size(transition_bits),
    _:bits,
  >> = transitions
  t
}

@target(erlang)
fn byte(bits: BitArray, i: Int) -> Int {
  let assert <<_:bytes-size(i), b, _:bits>> = bits
  b
}

@target(erlang)
@external(erlang, "erlang", "byte_size")
fn bit_array_bytes(bits: BitArray) -> Int

// --- The final rule ----------------------------------------------------------
//
// The final rule copies ICU's `TimeZone::getOffset`, `compareToRule` and
// `SimpleTimeZone::getOffset`, in seconds rather than milliseconds.

@target(erlang)
type Mode {
  DayOfMonth
  DayOfWeekInMonth
  DayOfWeekOnOrAfter
  DayOfWeekOnOrBefore
}

@target(erlang)
/// ICU's `SimpleTimeZone::TimeMode`.
const utc_time = 2

@target(erlang)
const wall_time = 0

@target(erlang)
const seconds_per_hour = 3600

@target(erlang)
fn final_offset(raw: Int, rule: Rule, unix_seconds: Int) -> #(Int, Bool) {
  let #(
    start_month,
    start_day,
    start_weekday,
    start_time,
    start_mode,
    end_month,
    end_day,
    end_weekday,
    end_time,
    end_mode,
    savings,
  ) = rule
  case start_day != 0 && end_day != 0 {
    False -> #(raw, False)
    True -> {
      let savings = case savings {
        0 -> seconds_per_hour
        _ -> savings
      }
      // ICU compares the rules with the local standard time.
      let local = unix_seconds + raw
      let day = data.floor_divide(local, seconds_per_day)
      let time = local - day * seconds_per_day
      let #(year, month, day_of_month) = data.civil_from_days(day)
      let month = month - 1
      // ICU counts weekdays from 1 for Sunday.
      let weekday = data.weekday(day) % days_per_week + 1
      let length = month_length(year, month)
      let previous_length = month_length(year, month - 1)
      let southern = start_month > end_month
      let start_compare =
        compare_to_rule(
          month,
          length,
          previous_length,
          day_of_month,
          weekday,
          time,
          case start_mode == utc_time {
            True -> -raw
            False -> 0
          },
          start_month,
          start_day,
          start_weekday,
          start_time,
        )
      let end_compare = case southern != { start_compare >= 0 } {
        True ->
          compare_to_rule(
            month,
            length,
            previous_length,
            day_of_month,
            weekday,
            time,
            case end_mode {
              _ if end_mode == wall_time -> savings
              _ if end_mode == utc_time -> -raw
              _ -> 0
            },
            end_month,
            end_day,
            end_weekday,
            end_time,
          )
        False -> 0
      }
      case
        { !southern && start_compare >= 0 && end_compare < 0 }
        || { southern && { start_compare >= 0 || end_compare < 0 } }
      {
        True -> #(raw + savings, True)
        False -> #(raw, False)
      }
    }
  }
}

@target(erlang)
/// -1, 0 or 1 as the time is before, at or after the rule's moment in
/// `rule_month`.
fn compare_to_rule(
  month: Int,
  length: Int,
  previous_length: Int,
  day_of_month: Int,
  weekday: Int,
  time: Int,
  delta: Int,
  rule_month: Int,
  rule_day: Int,
  rule_weekday: Int,
  rule_time: Int,
) -> Int {
  let #(month, day_of_month, weekday, time) =
    roll(month, length, previous_length, day_of_month, weekday, time + delta)
  case month < rule_month, month > rule_month {
    True, _ -> -1
    _, True -> 1
    False, False -> {
      let #(mode, rule_day, rule_weekday) = decode(rule_day, rule_weekday)
      let rule_day = int_min(rule_day, length)
      let rule_day_of_month = case mode {
        DayOfMonth -> rule_day
        DayOfWeekInMonth ->
          case rule_day > 0 {
            True ->
              1
              + { rule_day - 1 }
              * 7
              + { 7 + rule_weekday - { weekday - day_of_month + 1 } }
              % 7
            False ->
              length
              + { rule_day + 1 }
              * 7
              - { 7 + { weekday + length - day_of_month } - rule_weekday }
              % 7
          }
        DayOfWeekOnOrAfter ->
          rule_day
          + { 49 + rule_weekday - rule_day - weekday + day_of_month }
          % 7
        DayOfWeekOnOrBefore ->
          rule_day
          - { 49 - rule_weekday + rule_day + weekday - day_of_month }
          % 7
      }
      case day_of_month < rule_day_of_month, day_of_month > rule_day_of_month {
        True, _ -> -1
        _, True -> 1
        False, False ->
          case time < rule_time, time > rule_time {
            True, _ -> -1
            _, True -> 1
            False, False -> 0
          }
      }
    }
  }
}

@target(erlang)
/// Moves a time that's past the end or before the start of its day into the
/// next or previous day, like ICU's `compareToRule`.
fn roll(
  month: Int,
  length: Int,
  previous_length: Int,
  day_of_month: Int,
  weekday: Int,
  time: Int,
) -> #(Int, Int, Int, Int) {
  case time >= seconds_per_day, time < 0 {
    True, _ -> {
      let #(month, day_of_month) = case day_of_month + 1 > length {
        True -> #(month + 1, 1)
        False -> #(month, day_of_month + 1)
      }
      roll(
        month,
        length,
        previous_length,
        day_of_month,
        1 + weekday % 7,
        time - seconds_per_day,
      )
    }
    _, True -> {
      let #(month, day_of_month) = case day_of_month - 1 < 1 {
        True -> #(month - 1, previous_length)
        False -> #(month, day_of_month - 1)
      }
      roll(
        month,
        length,
        previous_length,
        day_of_month,
        1 + { weekday + 5 } % 7,
        time + seconds_per_day,
      )
    }
    False, False -> #(month, day_of_month, weekday, time)
  }
}

@target(erlang)
/// ICU's `SimpleTimeZone::decodeStartRule`: how a rule's day and weekday
/// pick a day.
fn decode(day: Int, weekday: Int) -> #(Mode, Int, Int) {
  case weekday {
    0 -> #(DayOfMonth, day, weekday)
    _ if weekday > 0 -> #(DayOfWeekInMonth, day, weekday)
    _ if day > 0 -> #(DayOfWeekOnOrAfter, day, -weekday)
    _ -> #(DayOfWeekOnOrBefore, -day, -weekday)
  }
}

// --- Gregorian dates ---------------------------------------------------------

@target(erlang)
/// Days in a month, from 0 for January. -1 is the December before.
fn month_length(year: Int, month: Int) -> Int {
  case month {
    -1 -> 31
    1 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    3 | 5 | 8 | 10 -> 30
    _ -> 31
  }
}

@target(erlang)
fn is_leap_year(year: Int) -> Bool {
  year % 4 == 0 && { year % 100 != 0 || year % 400 == 0 }
}

@target(erlang)
fn int_min(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

// --- Names -------------------------------------------------------------------

@target(erlang)
type Metazones

@target(erlang)
type Bundles

@target(erlang)
/// A locale's bundles of zone names, most specific first, by its tag.
@external(erlang, "glintl_generated_time_zones", "name_chain")
pub fn name_chain(tag: String) -> List(Int)

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "metazones")
fn metazones() -> Metazones

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "long_names")
fn long_names() -> Bundles

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "short_names")
fn short_names() -> Bundles

@target(erlang)
/// A byte for each zone key: 1 if any bundle has the zone's own long names.
@external(erlang, "glintl_generated_time_zones", "own_long_names")
fn own_long_names() -> BitArray

@target(erlang)
/// Like `own_long_names`, for short names.
@external(erlang, "glintl_generated_time_zones", "own_short_names")
fn own_short_names() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "words")
fn words() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "word_starts")
fn word_starts() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "name_words")
fn name_words() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "name_starts")
fn name_starts() -> BitArray

@target(erlang)
@external(erlang, "erlang", "element")
fn periods_of(position: Int, metazones: Metazones) -> BitArray

@target(erlang)
@external(erlang, "erlang", "element")
fn bundle(position: Int, bundles: Bundles) -> BitArray

@target(erlang)
@external(erlang, "erlang", "tuple_size")
fn key_count(metazones: Metazones) -> Int

@target(erlang)
const number_bits = 16

@target(erlang)
const start_bits = 24

@target(erlang)
const time_bits = 64

@target(erlang)
/// Each entry in a bundle is a key, then name numbers for standard and
/// daylight saving time.
const entry_bits = 48

@target(erlang)
/// Name number 1 stops a locale from using its parent's name. Real names
/// start at 2.
const blocked = 1

@target(erlang)
const first_name = 2

@target(erlang)
/// A zone's name at a moment in a locale, like ICU's
/// `TimeZoneNames::getDisplayName`: its own name if the locale has one, or
/// else its metazone's. `Error(Nil)` means ICU would show the offset.
pub fn name(
  chain: List(Int),
  key: Int,
  unix_seconds: Int,
  daylight: Bool,
  long: Bool,
) -> Result(String, Nil) {
  let #(table, own) = case long {
    True -> #(long_names(), own_long_names())
    False -> #(short_names(), own_short_names())
  }
  let all = metazones()
  let own_name = case byte(own, key) {
    0 -> Error(Nil)
    _ -> find_name(table, chain, key, daylight)
  }
  case own_name {
    Ok(n) -> Ok(name_text(n))
    Error(Nil) ->
      case metazone_at(periods_of(key + 1, all), unix_seconds) {
        Ok(metazone) ->
          case find_name(table, chain, key_count(all) + metazone, daylight) {
            Ok(n) -> Ok(name_text(n))
            Error(Nil) -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
  }
}

@target(erlang)
/// The name number for a key in the first bundle that has one, like ICU's
/// `ZNamesLoader`.
fn find_name(
  table: Bundles,
  chain: List(Int),
  key: Int,
  daylight: Bool,
) -> Result(Int, Nil) {
  case chain {
    [] -> Error(Nil)
    [first, ..rest] -> {
      let entries = bundle(first + 1, table)
      let count = bit_array_bytes(entries) * bits_per_byte / entry_bits
      case entry(entries, key, 0, count) {
        Ok(#(standard, summer)) -> {
          let n = case daylight {
            True -> summer
            False -> standard
          }
          case n {
            0 -> find_name(table, rest, key, daylight)
            _ if n == blocked -> Error(Nil)
            _ -> Ok(n)
          }
        }
        Error(Nil) -> find_name(table, rest, key, daylight)
      }
    }
  }
}

@target(erlang)
/// The standard and daylight saving names for `key` in a bundle's sorted
/// entries, found by binary search between `low` and `high`.
fn entry(
  entries: BitArray,
  key: Int,
  low: Int,
  high: Int,
) -> Result(#(Int, Int), Nil) {
  case low >= high {
    True -> Error(Nil)
    False -> {
      let middle = { low + high } / 2
      let assert <<
        _:bits-size(middle * entry_bits),
        found:size(number_bits),
        standard:size(number_bits),
        daylight:size(number_bits),
        _:bits,
      >> = entries
      case found == key, found < key {
        True, _ -> Ok(#(standard, daylight))
        False, True -> entry(entries, key, middle + 1, high)
        False, False -> entry(entries, key, low, middle)
      }
    }
  }
}

@target(erlang)
/// The metazone a key is in at a moment, like ICU's `getMetaZoneID`.
fn metazone_at(periods: BitArray, unix_seconds: Int) -> Result(Int, Nil) {
  case periods {
    <<
      metazone:size(number_bits),
      from:signed-size(time_bits),
      to:signed-size(time_bits),
      rest:bits,
    >> ->
      case from <= unix_seconds && unix_seconds < to {
        True -> Ok(metazone)
        False -> metazone_at(rest, unix_seconds)
      }
    _ -> Error(Nil)
  }
}

@target(erlang)
/// Where item `i` starts and ends. The data stores each item's start, then
/// where the last one ends.
fn span(starts: BitArray, i: Int) -> #(Int, Int) {
  let assert <<
    _:bits-size(i * start_bits),
    from:size(start_bits),
    to:size(start_bits),
    _:bits,
  >> = starts
  #(from, to)
}

@target(erlang)
/// A name's text, joined from its words.
fn name_text(n: Int) -> String {
  let #(from, to) = span(name_starts(), n - first_name)
  // The generator writes the words, so they're always valid UTF-8.
  join(word_list(name_words(), from, to))
}

@target(erlang)
fn word_list(numbers: BitArray, i: Int, end: Int) -> List(BitArray) {
  case i >= end {
    True -> []
    False -> {
      let assert <<_:bits-size(i * number_bits), w:size(number_bits), _:bits>> =
        numbers
      let #(from, to) = span(word_starts(), w)
      let assert <<_:bytes-size(from), word:bytes-size(to - from), _:bits>> =
        words()
      [word, ..word_list(numbers, i + 1, end)]
    }
  }
}

@target(erlang)
@external(erlang, "erlang", "iolist_to_binary")
fn join(words: List(BitArray)) -> String
