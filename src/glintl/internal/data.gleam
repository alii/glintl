//// `codegen/generate.ts` writes the calendar maths as these Erlang terms, so
//// keep the two in sync.

/// The same as `glintl.Style`, which this module can't use.
pub type Style {
  Full
  Long
  Medium
  Short
}

/// What a formatter shows.
pub type Shown {
  DateOnly(Style)
  TimeOnly(Style)
  DateAndTime(date: Style, time: Style)
}

/// How a calendar maps days to its own dates. The same for every locale.
pub type Math {
  /// Gregorian months, with eras and years given by `eras`, newest first.
  /// Days before `julian_before` are in the Julian calendar, as ICU does by
  /// default for calendars other than Gregorian.
  Proleptic(eras: List(EraRule), julian_before: Int)
  /// Whole years from a table, made from ICU. Years are numbered from 0.
  Table(
    /// Chinese and Dangi, which have related years and a 60 year cycle.
    cyclic: Bool,
    /// The first day of the first year.
    first_day: Int,
    /// The day after the last year.
    end_day: Int,
    /// How many numbers `starts` holds.
    start_count: Int,
    /// The first day of each year, then the day after the last year.
    starts: HomogenousUnknownLengthTuple(Int),
    /// Each year's month layout.
    layouts: HomogenousUnknownLengthTuple(Int),
    /// Each layout: a byte for each month's number, then its length in days.
    months: HomogenousUnknownLengthTuple(BitArray),
    /// Newest first.
    years: List(YearRule),
    /// Days that ICU calls day 0 of a month, as `#(day, month number)`.
    /// ICU's Chinese calendar makes a few of these, where its astronomy goes
    /// wrong.
    day_zero: List(#(Int, Int)),
  )
  NoMath
}

/// Stands in for the start of time: a day earlier than any glintl formats,
/// in days since 1970-01-01. The generator writes the same number.
pub const start_of_time = -1_000_000_000_000

/// 1 January AD 1, in days since 1970-01-01.
pub const first_day_of_ad = -719_162

/// The Gregorian calendar's eras, numbered newest first like generated eras.
const anno_domini = 0

const before_christ = 1

/// The Gregorian calendar's maths. AD years are astronomical years, and BC
/// years count back from 1 BC, which is astronomical year 0.
/// `codegen/generate.ts` checks it against ICU.
pub const gregorian =
  Proleptic(
    [gregorian_newest_era, gregorian_oldest_era],
    julian_before: start_of_time,
  )

pub const gregorian_newest_era =
  EraRule(start: first_day_of_ad, era: anno_domini, base: 0, sign: 1)

pub const gregorian_oldest_era =
  EraRule(start: start_of_time, era: before_christ, base: 1, sign: -1)

pub const gregorian_older_eras = [gregorian_oldest_era]

/// From `start` until the next era, the year is `base + sign * y`, where `y`
/// is the astronomical Gregorian year (1 BC is 0).
pub type EraRule {
  EraRule(start: Int, era: Int, base: Int, sign: Int)
}

/// From year `from` until the next rule, each year adds `year_step` to the
/// year and 1 to the extended year. In cyclic calendars it also adds 1 to the
/// related year and the cycle.
pub type YearRule {
  YearRule(
    from: Int,
    era: Int,
    year: Int,
    year_step: Int,
    extended: Int,
    related: Int,
    cycle: Int,
  )
}

/// An Erlang tuple, for reading by position in constant time.
pub type HomogenousUnknownLengthTuple(a)

/// A moment as seen in a calendar: one record per format, to keep
/// allocation down. `month` is an index into the calendar's month names.
/// `year_start` and `next_year_start` are `start_of_time` when they haven't
/// been worked out, which only happens for calendars with Gregorian months.
pub type Local {
  Local(
    epoch_day: Int,
    hour: Int,
    minute: Int,
    second: Int,
    offset_minutes: Int,
    unix_seconds: Int,
    era: Int,
    year: Int,
    extended: Int,
    related: Int,
    cycle: Int,
    month: Int,
    day: Int,
    year_start: Int,
    next_year_start: Int,
  )
}
