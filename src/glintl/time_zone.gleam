//// A time zone says where to show a moment. It's either a place like London,
//// whose offset changes with summer time, or a fixed offset from UTC.
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

/// Where to show times.
pub opaque type TimeZone {
  /// A whole number of minutes ahead of UTC, under 24 hours either way.
  Offset(minutes: Int)
  /// A zone from the IANA time zone database. On Erlang, `zone` is its number
  /// in glintl's data.
  Named(name: String, zone: Int)
}

/// UTC itself, with no offset.
pub const utc = Offset(minutes: 0)

/// A place's time zone by its IANA name, like `"Europe/London"` or
/// `"America/New_York"`. Like Intl, it takes old names like `"GB"` too, and
/// case doesn't matter. Summer time is worked out for each moment you format.
///
/// It returns `Error(Nil)` for a name glintl doesn't know.
///
/// On Erlang, glintl can't show time zone names like "British Summer Time"
/// yet, so it shows the offset instead, like "GMT+1".
pub fn from_name(name: String) -> Result(TimeZone, Nil) {
  find(name)
}

/// The computer's own time zone, the one Intl uses when you don't give it
/// one. In a browser, that's the user's zone.
///
/// On Erlang it comes from the `TZ` setting, or else from `/etc/localtime` or
/// `/etc/timezone`. It returns `Error(Nil)` if none of them names a zone
/// glintl knows.
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
    Ok(#(name, zone)) -> Ok(Named(name:, zone:))
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
        Ok(name) -> Ok(Named(name:, zone: 0))
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

/// Why an offset couldn't be made.
pub type OffsetError {
  /// `hours` and `minutes` have different signs, like
  /// `offset(hours: -3, minutes: 30)`.
  MixedSigns
  /// `minutes` is an hour or more either way.
  MinutesTooLarge
  /// The offset is 24 hours or more either way.
  OffsetTooLarge
}

/// Makes a time zone `hours` and `minutes` ahead of UTC, like
/// `offset(hours: 5, minutes: 30)` for India. Behind UTC both are negative,
/// like `offset(hours: -3, minutes: -30)` for Newfoundland.
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

/// Makes a time zone a `gleam_time` duration ahead of UTC, like
/// `calendar.local_offset()`. It rounds down to whole minutes.
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
/// How many seconds the time zone is ahead of UTC at a moment.
@internal
pub fn offset_seconds(zone: TimeZone, unix_seconds: Int) -> Int {
  case zone {
    Offset(minutes:) -> minutes * seconds_per_minute
    Named(zone:, ..) -> zones.offset_seconds(zone, unix_seconds)
  }
}

/// The time zone as Intl's `timeZone` option, like `"Europe/London"` or
/// `"+05:30"`.
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
