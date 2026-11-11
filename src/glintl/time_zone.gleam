//// Time zones, which say where to show a moment. For now a time zone is a
//// fixed offset from UTC.
////
//// ```gleam
//// import gleam/time/calendar
//// import glintl/time_zone
////
//// let india = time_zone.offset(hours: 5, minutes: 30)
//// let here = time_zone.from_duration(calendar.local_offset())
//// ```

import gleam/int
import gleam/time/duration.{type Duration}

/// Where to show times. It's a whole number of minutes ahead of UTC, under
/// 24 hours either way.
pub opaque type TimeZone {
  TimeZone(minutes: Int)
}

/// UTC itself, with no offset.
pub const utc = TimeZone(minutes: 0)

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

/// A time zone `hours` and `minutes` ahead of UTC, like
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

/// A time zone a `gleam_time` duration ahead of UTC, like
/// `calendar.local_offset()`, rounded down to whole minutes.
pub fn from_duration(duration: Duration) -> Result(TimeZone, OffsetError) {
  let #(seconds, _) = duration.to_seconds_and_nanoseconds(duration)
  let remainder =
    { seconds % seconds_per_minute + seconds_per_minute } % seconds_per_minute
  from_minutes({ seconds - remainder } / seconds_per_minute)
}

fn from_minutes(minutes: Int) -> Result(TimeZone, OffsetError) {
  case int.absolute_value(minutes) < hours_per_day * minutes_per_hour {
    True -> Ok(TimeZone(minutes:))
    False -> Error(OffsetTooLarge)
  }
}

/// How many minutes the time zone is ahead of UTC.
@internal
pub fn offset_minutes(zone: TimeZone) -> Int {
  zone.minutes
}
