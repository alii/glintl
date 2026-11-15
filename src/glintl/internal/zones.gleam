//// Finds a named time zone's offset and name at a moment on Erlang, the same
//// way as ICU's `OlsonTimeZone` and `TimeZoneNames`. `codegen/zones.ts` writes
//// the data.

@target(erlang)
import gleam/result
@target(erlang)
import gleam/string
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

// --- Generic names -----------------------------------------------------------
//
// Generic names copy ICU's `TZGNCore`: a zone's own generic name, or else its
// metazone's, or else a name for its location, like "Los Angeles Time".

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "long_generic_names")
fn long_generic_names() -> Bundles

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "short_generic_names")
fn short_generic_names() -> Bundles

@target(erlang)
/// A byte for each zone key: 1 if any bundle has the zone's own long
/// generic name.
@external(erlang, "glintl_generated_time_zones", "own_long_generic_names")
fn own_long_generic_names() -> BitArray

@target(erlang)
/// Like `own_long_generic_names`, for short names.
@external(erlang, "glintl_generated_time_zones", "own_short_generic_names")
fn own_short_generic_names() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "cities")
fn cities() -> Bundles

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "region_names")
fn region_names() -> Bundles

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "region_codes")
fn region_codes() -> data.HomogenousUnknownLengthTuple(String)

@target(erlang)
/// For each zone key, its country as a region number plus 1, or 0 for none,
/// then 1 if it's the country's main zone.
@external(erlang, "glintl_generated_time_zones", "countries")
fn countries() -> BitArray

@target(erlang)
/// Each metazone's zone key in each region, sorted by region.
@external(erlang, "glintl_generated_time_zones", "golden_zones")
fn golden_zones() -> data.HomogenousUnknownLengthTuple(BitArray)

@target(erlang)
/// Each zone key's number in the rules.
@external(erlang, "glintl_generated_time_zones", "key_zones")
fn key_zones() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "world_region")
fn world_region() -> Int

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "labels")
fn labels() -> BitArray

@target(erlang)
@external(erlang, "glintl_generated_time_zones", "label_starts")
fn label_starts() -> BitArray

@target(erlang)
@external(erlang, "erlang", "element")
fn golden_of(
  position: Int,
  zones: data.HomogenousUnknownLengthTuple(BitArray),
) -> BitArray

@target(erlang)
@external(erlang, "erlang", "element")
fn code_of(
  position: Int,
  codes: data.HomogenousUnknownLengthTuple(String),
) -> String

@target(erlang)
/// What a locale needs for location names, by its tag.
@external(erlang, "glintl_generated_time_zones", "location")
pub fn location(tag: String) -> data.Location

@target(erlang)
/// ICU's `kDstCheckRange`: a zone uses standard names if it has no summer
/// time this close to the moment.
const dst_check_range = 15_897_600

@target(erlang)
/// Each entry in a generic name, city or country table is a key, then a
/// name number.
const single_bits = 32

@target(erlang)
/// Each zone key's country is a 16-bit region number, then a byte.
const country_bytes = 3

@target(erlang)
const key_zone_bytes = 2

@target(erlang)
/// A zone's generic name at a moment, like ICU's
/// `TimeZoneGenericNames::getDisplayName`. `Error(Nil)` means ICU would show
/// the offset.
pub fn generic_name(
  chain: List(Int),
  location: data.Location,
  key: Int,
  zone: Int,
  unix_seconds: Int,
  long: Bool,
) -> Result(String, Nil) {
  case non_location_name(chain, location, key, zone, unix_seconds, long) {
    Ok(name) -> Ok(name)
    Error(Nil) -> location_name(chain, location, key)
  }
}

@target(erlang)
/// ICU's `formatGenericNonLocationName`.
fn non_location_name(
  chain: List(Int),
  location: data.Location,
  key: Int,
  zone: Int,
  unix_seconds: Int,
  long: Bool,
) -> Result(String, Nil) {
  let #(table, own) = case long {
    True -> #(long_generic_names(), own_long_generic_names())
    False -> #(short_generic_names(), own_short_generic_names())
  }
  let own_name = case byte(own, key) {
    0 -> Error(Nil)
    _ -> find_single(table, chain, key)
  }
  let all = metazones()
  case own_name, metazone_at(periods_of(key + 1, all), unix_seconds) {
    Ok(n), _ -> Ok(name_text(n))
    Error(Nil), Error(Nil) -> Error(Nil)
    Error(Nil), Ok(metazone) -> {
      let generic =
        find_single(table, chain, key_count(all) + metazone)
        |> result.map(name_text)
      let #(raw, dst) = offset_parts(zone, unix_seconds)
      case standard_name(chain, key, zone, unix_seconds, long, dst, generic) {
        Ok(name) -> Ok(name)
        Error(Nil) ->
          case generic {
            Error(Nil) -> Error(Nil)
            Ok(generic) ->
              metazone_name(
                chain,
                location,
                key,
                metazone,
                unix_seconds + raw + dst,
                raw,
                dst,
                generic,
              )
          }
      }
    }
  }
}

@target(erlang)
/// A zone with no summer time near the moment uses its standard name, unless
/// that's the same as its metazone's generic name.
fn standard_name(
  chain: List(Int),
  key: Int,
  zone: Int,
  unix_seconds: Int,
  long: Bool,
  dst: Int,
  generic: Result(String, Nil),
) -> Result(String, Nil) {
  case dst == 0 && !dst_nearby(zone, unix_seconds) {
    False -> Error(Nil)
    True ->
      case name(chain, key, unix_seconds, False, long), generic {
        Ok(standard), Ok(generic) ->
          case string.lowercase(standard) == string.lowercase(generic) {
            True -> Error(Nil)
            False -> Ok(standard)
          }
        Ok(standard), Error(Nil) -> Ok(standard)
        Error(Nil), _ -> Error(Nil)
      }
  }
}

@target(erlang)
/// The metazone's generic name, or a partial location name like "Pacific
/// Time (Canada)" if the zone's offset differs from the metazone's zone for
/// the locale's region at the same wall time.
fn metazone_name(
  chain: List(Int),
  location: data.Location,
  key: Int,
  metazone: Int,
  wall_seconds: Int,
  raw: Int,
  dst: Int,
  generic: String,
) -> Result(String, Nil) {
  case golden_for(metazone, location.region) {
    Ok(golden) if golden != key -> {
      let #(golden_raw, golden_dst) =
        offset_parts_at_wall(key_zone(golden), wall_seconds)
      case raw != golden_raw || dst != golden_dst {
        False -> Ok(generic)
        True -> partial_location_name(chain, location, key, metazone, generic)
      }
    }
    _ -> Ok(generic)
  }
}

@target(erlang)
/// ICU's `getPartialLocationName`: the country if the zone is the metazone's
/// zone there, or else the city.
fn partial_location_name(
  chain: List(Int),
  location: data.Location,
  key: Int,
  metazone: Int,
  generic: String,
) -> Result(String, Nil) {
  let place = case country_of(key) {
    Ok(#(region, _)) ->
      case golden_for(metazone, region) {
        Ok(golden) if golden == key -> Ok(country_name(location, region))
        _ -> city(chain, key)
      }
    Error(Nil) -> city(chain, key)
  }
  case place {
    Ok(place) ->
      Ok(
        location.fallback_format
        |> string.replace("{0}", place)
        |> string.replace("{1}", generic),
      )
    Error(Nil) -> Error(Nil)
  }
}

@target(erlang)
/// ICU's `getGenericLocationName`: the country for its main zone, and the
/// city for the others.
fn location_name(
  chain: List(Int),
  location: data.Location,
  key: Int,
) -> Result(String, Nil) {
  let place = case country_of(key) {
    Ok(#(region, True)) -> Ok(country_name(location, region))
    Ok(#(_, False)) -> city(chain, key)
    Error(Nil) -> Error(Nil)
  }
  case place {
    Ok(place) -> Ok(string.replace(location.region_format, "{0}", place))
    Error(Nil) -> Error(Nil)
  }
}

@target(erlang)
/// A zone's country, and whether it's the country's main zone.
fn country_of(key: Int) -> Result(#(Int, Bool), Nil) {
  let assert <<_:bytes-size(key * country_bytes), region:16, main, _:bits>> =
    countries()
  case region {
    0 -> Error(Nil)
    _ -> Ok(#(region - 1, main == 1))
  }
}

@target(erlang)
/// A country's name, or its code where the locale has none, like ICU's
/// `LocaleDisplayNames::regionDisplayName`.
fn country_name(location: data.Location, region: Int) -> String {
  case find_single(region_names(), location.regions, region) {
    Ok(n) -> label_text(n)
    Error(Nil) -> code_of(region + 1, region_codes())
  }
}

@target(erlang)
fn city(chain: List(Int), key: Int) -> Result(String, Nil) {
  find_single(cities(), chain, key) |> result.map(label_text)
}

@target(erlang)
fn label_text(n: Int) -> String {
  let #(from, to) = span(label_starts(), n - first_name)
  let assert <<_:bytes-size(from), text:bytes-size(to - from), _:bits>> =
    labels()
  join([text])
}

@target(erlang)
/// ICU's `getReferenceZoneID`: a metazone's zone in a region, or else its
/// zone for the world.
fn golden_for(metazone: Int, region: Int) -> Result(Int, Nil) {
  let zones = golden_of(metazone + 1, golden_zones())
  case golden_in(zones, region) {
    Ok(key) -> Ok(key)
    Error(Nil) -> golden_in(zones, world_region())
  }
}

@target(erlang)
fn golden_in(zones: BitArray, region: Int) -> Result(Int, Nil) {
  case zones {
    <<r:size(number_bits), key:size(number_bits), _:bits>> if r == region ->
      Ok(key)
    <<_:size(number_bits), _:size(number_bits), rest:bits>> ->
      golden_in(rest, region)
    _ -> Error(Nil)
  }
}

@target(erlang)
fn key_zone(key: Int) -> Int {
  let assert <<_:bytes-size(key * key_zone_bytes), zone:16, _:bits>> =
    key_zones()
  zone
}

@target(erlang)
/// Like `find_name`, for tables with one name for each key.
fn find_single(table: Bundles, chain: List(Int), key: Int) -> Result(Int, Nil) {
  case chain {
    [] -> Error(Nil)
    [first, ..rest] -> {
      let entries = bundle(first + 1, table)
      let count = bit_array_bytes(entries) * bits_per_byte / single_bits
      case single(entries, key, 0, count) {
        Ok(n) if n == blocked -> Error(Nil)
        Ok(n) -> Ok(n)
        Error(Nil) -> find_single(table, rest, key)
      }
    }
  }
}

@target(erlang)
fn single(
  entries: BitArray,
  key: Int,
  low: Int,
  high: Int,
) -> Result(Int, Nil) {
  case low >= high {
    True -> Error(Nil)
    False -> {
      let middle = { low + high } / 2
      let assert <<
        _:bits-size(middle * single_bits),
        found:size(number_bits),
        n:size(number_bits),
        _:bits,
      >> = entries
      case found == key, found < key {
        True, _ -> Ok(n)
        False, True -> single(entries, key, middle + 1, high)
        False, False -> single(entries, key, low, middle)
      }
    }
  }
}

@target(erlang)
/// How many seconds of a zone's offset are standard time, then summer time.
fn offset_parts(zone: Int, unix_seconds: Int) -> #(Int, Int) {
  let Rules(transitions:, types:, type_map:, final:) =
    element(zone + 1, table())
  case final {
    Final(raw:, year:, rule:) ->
      case unix_seconds >= data.days_from_civil(year, 1, 1) * seconds_per_day {
        True -> {
          let #(total, _) = final_offset(raw, rule, unix_seconds)
          #(raw, total - raw)
        }
        False -> historical_parts(transitions, types, type_map, unix_seconds)
      }
    NoFinal -> historical_parts(transitions, types, type_map, unix_seconds)
  }
}

@target(erlang)
/// ICU's longest offset either way, `MAX_OFFSET_SECONDS`.
const max_offset = 86_400

@target(erlang)
/// Like `offset_parts`, at a wall time, like ICU's `getOffset` with `local`
/// true. A wall time that happens twice, or not at all, gets the offset after
/// the change.
fn offset_parts_at_wall(zone: Int, wall_seconds: Int) -> #(Int, Int) {
  let Rules(transitions:, types:, type_map:, final:) =
    element(zone + 1, table())
  case final {
    Final(raw:, year:, rule:) ->
      case wall_seconds >= data.days_from_civil(year, 1, 1) * seconds_per_day {
        // ICU's `TimeZone::getOffset` reads the wall time as standard time,
        // then again as summer time if that finds summer time.
        True -> {
          let #(first, _) = final_offset(raw, rule, wall_seconds - raw)
          case first - raw {
            0 -> #(raw, 0)
            dst -> {
              let #(second, _) =
                final_offset(raw, rule, wall_seconds - raw - dst)
              #(raw, second - raw)
            }
          }
        }
        False ->
          historical_parts_at_wall(transitions, types, type_map, wall_seconds)
      }
    NoFinal ->
      historical_parts_at_wall(transitions, types, type_map, wall_seconds)
  }
}

@target(erlang)
/// ICU's `getHistoricalOffset` with `kFormer` and `kLatter`: the last change
/// whose wall time, with the offset after it, is at or before `wall_seconds`.
fn historical_parts_at_wall(
  transitions: BitArray,
  types: BitArray,
  type_map: BitArray,
  wall_seconds: Int,
) -> #(Int, Int) {
  let count = bit_array_bytes(transitions) * bits_per_byte / transition_bits
  let last = last_at_or_before(transitions, wall_seconds + max_offset, 0, count)
  type_parts(types, wall_type(transitions, types, type_map, wall_seconds, last))
}

@target(erlang)
fn wall_type(
  transitions: BitArray,
  types: BitArray,
  type_map: BitArray,
  wall_seconds: Int,
  i: Int,
) -> Int {
  case i < 0 {
    True -> 0
    False -> {
      let after = byte(type_map, i)
      let #(raw, dst) = type_parts(types, after)
      case wall_seconds >= transition(transitions, i) + raw + dst {
        True -> after
        False -> wall_type(transitions, types, type_map, wall_seconds, i - 1)
      }
    }
  }
}

@target(erlang)
fn historical_parts(
  transitions: BitArray,
  types: BitArray,
  type_map: BitArray,
  unix_seconds: Int,
) -> #(Int, Int) {
  let count = bit_array_bytes(transitions) * bits_per_byte / transition_bits
  case last_at_or_before(transitions, unix_seconds, 0, count) {
    -1 -> type_parts(types, 0)
    i -> type_parts(types, byte(type_map, i))
  }
}

@target(erlang)
fn type_parts(types: BitArray, type_: Int) -> #(Int, Int) {
  let assert <<
    _:bits-size(type_ * type_bits),
    raw:signed-size(offset_bits),
    dst:signed-size(offset_bits),
    _:bits,
  >> = types
  #(raw, dst)
}

@target(erlang)
/// Whether a zone changes to or from summer time within `dst_check_range` of
/// the moment, like ICU's check with `getPreviousTransition` and
/// `getNextTransition`.
fn dst_nearby(zone: Int, unix_seconds: Int) -> Bool {
  let Rules(transitions:, types:, type_map:, final:) =
    element(zone + 1, table())
  let final_start = case final {
    Final(year:, ..) -> data.days_from_civil(year, 1, 1) * seconds_per_day
    NoFinal -> 0
  }
  case final {
    // A yearly rule with summer time always has a change within half a year.
    Final(rule:, ..) if unix_seconds >= final_start -> rule.1 != 0 && rule.6 != 0
    _ -> {
      let count = bit_array_bytes(transitions) * bits_per_byte / transition_bits
      let i = last_at_or_before(transitions, unix_seconds, 0, count)
      let before = case i >= 0 {
        True -> {
          let from = case i {
            0 -> 0
            _ -> byte(type_map, i - 1)
          }
          unix_seconds - transition(transitions, i) < dst_check_range
          && type_parts(types, from).1 != 0
        }
        False -> False
      }
      let after = case i + 1 < count, final {
        True, _ ->
          transition(transitions, i + 1) - unix_seconds < dst_check_range
          && type_parts(types, byte(type_map, i + 1)).1 != 0
        // The next change comes from the yearly rule, so look for it.
        False, Final(..) -> summer_within(zone, unix_seconds, 1)
        False, NoFinal -> False
      }
      before || after
    }
  }
}

@target(erlang)
fn summer_within(zone: Int, unix_seconds: Int, day: Int) -> Bool {
  let later = unix_seconds + day * seconds_per_day
  case later - unix_seconds < dst_check_range {
    False -> False
    True ->
      case offset(zone, later) {
        #(_, True) -> True
        #(_, False) -> summer_within(zone, unix_seconds, day + 1)
      }
  }
}
