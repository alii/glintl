//// This module is for picking the time zone to show a moment in. A time zone is
//// either a place like London or a fixed offset from UTC. A place's offset changes
//// with summer time, and glintl works out the right one for each moment it
//// formats.
////
//// ```gleam
//// import gleam/time/calendar
//// import glintl/time_zone
////
//// let london = time_zone.from_name("Europe/London")
//// let here = time_zone.local()
//// let india = time_zone.offset(hours: 5, minutes: 30)
//// let offset_now = time_zone.from_duration(calendar.local_offset())
//// ```

import gleam/int
import gleam/string
import gleam/time/duration.{type Duration}
@target(erlang)
import glintl/internal/zones

/// Either a place like London or a fixed offset from UTC.
pub opaque type TimeZone {
  /// Minutes ahead of UTC. It's always less than a day either way.
  Offset(minutes: Int)
  /// A zone from the IANA database. On Erlang, `zone` and `key` say where its
  /// rules and names are in glintl's data.
  Named(name: String, zone: Int, key: Int)
}

/// The UTC time zone.
pub const utc = Offset(minutes: 0)

/// Get a place's time zone from its IANA name.
///
/// ```gleam
/// time_zone.from_name("Europe/London")
/// ```
///
/// Like Intl, it also accepts old names such as `"GB"`. It returns an error for a
/// name glintl doesn't know.
///
/// ```gleam
/// time_zone.from_name("Mars/Olympus_Mons")
/// // -> Error(Nil)
/// ```
pub fn from_name(name: String) -> Result(TimeZone, Nil) {
  find(name)
}

/// Get the computer's time zone. Intl uses this zone when you don't give one,
/// and in a browser it's the user's zone.
///
/// On Erlang, glintl reads it from the `TZ` environment variable, or else from
/// `/etc/localtime` or `/etc/timezone`. It returns an error if none of them name a
/// zone glintl knows.
pub fn local() -> Result(TimeZone, Nil) {
  case local_name() {
    Ok(name) -> from_name(name)
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "glintl_ffi", "local_time_zone")
@external(javascript, "../glintl_ffi.mjs", "localTimeZone")
fn local_name() -> Result(String, Nil)

@target(erlang)
fn find(name: String) -> Result(TimeZone, Nil) {
  case zones.find(string.lowercase(name)) {
    Ok(#(name, zone, key)) -> Ok(Named(name:, zone:, key:))
    Error(Nil) -> Error(Nil)
  }
}

@target(javascript)
fn find(name: String) -> Result(TimeZone, Nil) {
  // Intl also takes offsets as names, which `offset` is for.
  case string.starts_with(name, "+") || string.starts_with(name, "-") {
    True -> Error(Nil)
    False ->
      case intl_name(name) {
        Ok(name) -> Ok(Named(name:, zone: 0, key: 0))
        Error(Nil) -> Error(Nil)
      }
  }
}

@target(javascript)
@external(javascript, "../glintl_ffi.mjs", "timeZoneName")
fn intl_name(name: String) -> Result(String, Nil)

const seconds_per_minute = 60

const minutes_per_hour = 60

const hours_per_day = 24

/// Why `offset` or `from_duration` couldn't make a time zone.
pub type OffsetError {
  /// One of `hours` and `minutes` is negative and the other is positive.
  MixedSigns
  /// `minutes` is an hour or more either way.
  MinutesTooLarge
  /// The offset is a day or more either way.
  OffsetTooLarge
}

/// Make a time zone that's a fixed number of hours and minutes ahead of UTC.
/// For India, that's 5 hours and 30 minutes.
///
/// ```gleam
/// time_zone.offset(hours: 5, minutes: 30)
/// ```
///
/// For a zone behind UTC, make both numbers negative. Newfoundland is 3 hours
/// and 30 minutes behind.
///
/// ```gleam
/// time_zone.offset(hours: -3, minutes: -30)
/// ```
pub fn offset(
  hours hours: Int,
  minutes minutes: Int,
) -> Result(TimeZone, OffsetError) {
  let same_sign =
    { hours >= 0 && minutes >= 0 } || { hours <= 0 && minutes <= 0 }
  case same_sign, int.absolute_value(minutes) < minutes_per_hour {
    False, _ -> Error(MixedSigns)
    True, False -> Error(MinutesTooLarge)
    True, True -> from_minutes(hours * minutes_per_hour + minutes)
  }
}

/// Make a time zone that's a fixed duration ahead of UTC. This is useful with
/// gleam_time's `calendar.local_offset`.
///
/// ```gleam
/// time_zone.from_duration(calendar.local_offset())
/// ```
///
/// The duration is rounded down to whole minutes.
pub fn from_duration(duration: Duration) -> Result(TimeZone, OffsetError) {
  let #(seconds, _) = duration.to_seconds_and_nanoseconds(duration)
  let remainder =
    { seconds % seconds_per_minute + seconds_per_minute } % seconds_per_minute
  from_minutes({ seconds - remainder } / seconds_per_minute)
}

fn from_minutes(minutes: Int) -> Result(TimeZone, OffsetError) {
  case int.absolute_value(minutes) < hours_per_day * minutes_per_hour {
    True -> Ok(Offset(minutes:))
    False -> Error(OffsetTooLarge)
  }
}

@target(erlang)
/// Returns the offset in seconds, the names key, the rules number and whether
/// it's summer time. A fixed offset has -1 for both numbers.
@internal
pub fn at(zone: TimeZone, unix_seconds: Int) -> #(Int, Int, Int, Bool) {
  case zone {
    Offset(minutes:) -> #(minutes * seconds_per_minute, -1, -1, False)
    Named(zone:, key:, ..) -> {
      let #(offset, daylight) = zones.offset(zone, unix_seconds)
      #(offset, key, zone, daylight)
    }
  }
}

/// Writes the zone as Intl's `timeZone` option, like `"+05:30"` for an offset.
@internal
pub fn intl_time_zone(zone: TimeZone) -> String {
  case zone {
    Named(name:, ..) -> name
    Offset(minutes:) -> {
      let sign = case minutes < 0 {
        True -> "-"
        False -> "+"
      }
      let minutes = int.absolute_value(minutes)
      sign
      <> pad(minutes / minutes_per_hour)
      <> ":"
      <> pad(minutes % minutes_per_hour)
    }
  }
}

fn pad(n: Int) -> String {
  string.pad_start(int.to_string(n), to: 2, with: "0")
}
