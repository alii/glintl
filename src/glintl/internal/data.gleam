//// `codegen/generate.ts` writes these as Erlang terms, so keep the two in
//// sync.

/// A locale's Gregorian formats. `NoData` on JavaScript, where
/// `Intl.DateTimeFormat` is used.
pub type Data {
  Data(digits: Digits, gregorian: Formats)
  NoData
}

/// A locale's formats for every other calendar, in the order of
/// `glintl.Calendar`. Kept apart from `Data` so they are only loaded when
/// used.
pub type Calendars {
  Calendars(formats: List(Formats))
  NoCalendars
}

pub type Digits {
  /// `0` to `9`.
  Ascii
  /// Ten strings, for zero to nine.
  Digits(List(String))
}

/// Patterns for each style, from full to short.
pub type Formats {
  Formats(
    dates: List(Pattern),
    times: List(Pattern),
    glues: List(Glue),
    eras: List(EraFormats),
  )
}

/// Date patterns for an era that ICU formats differently from the rest.
/// `combined` holds dates with times, by date style then time style, for
/// eras where ICU doesn't just join the two. It's empty otherwise.
pub type EraFormats {
  EraFormats(era: Int, dates: List(Pattern), combined: List(Pattern))
}

/// How a date and a time are joined, like `{date} at {time}`.
pub type Glue =
  List(GluePiece)

pub type GluePiece {
  GlueText(String)
  GlueDate
  GlueTime
}

pub type Pattern =
  List(Token)

pub type Token {
  Literal(String)
  /// A part written with ASCII digits, whatever the locale's digits are.
  AsciiDigits(Token)
  /// `first` is how year 1 is written when it isn't a number, like 元.
  Year(two_digit: Bool, minus: String, first: String)
  /// ICU's week-based year. Weeks start on `first_day`, 1 for Monday to 7
  /// for Sunday. `exceptions` holds the first day of years where ICU starts
  /// them somewhere else, as `#(extended year, day)`.
  WeekYear(
    minus: String,
    first_day: Int,
    minimal_days: Int,
    exceptions: List(#(Int, Int)),
  )
  /// ICU's extended year, which runs on through eras.
  ExtendedYear(minus: String)
  RelatedYear
  /// Sixty names, for the years of the Chinese cycle.
  YearName(names: List(String))
  MonthNumber(pad: Bool)
  /// Names by month number. In calendars with leap months this includes them.
  MonthName(names: List(String))
  Day(pad: Bool)
  /// Names for days 0 to 30. Day 0 only happens on the few days where ICU's
  /// Chinese calendar goes wrong.
  DayName(names: List(String))
  /// Seven names, Sunday first.
  Weekday(names: List(String))
  /// Names by era number.
  Era(names: List(String))
  Hour(pad: Bool, cycle: HourCycle)
  Minute(pad: Bool)
  Second(pad: Bool)
  /// One name per hour. Some locales have special words for exactly
  /// midnight and noon.
  DayPeriod(by_hour: List(String), midnight: String, noon: String)
  /// Such as `GMT+5:30`.
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
}

pub type HourCycle {
  /// 0 to 11.
  H11
  /// 1 to 12.
  H12
  /// 0 to 23.
  H23
  /// 1 to 24.
  H24
}

/// How a calendar maps days to its own dates. The same for every locale.
pub type Math {
  /// Gregorian months, with eras and years given by `eras`, newest first.
  Proleptic(eras: List(EraRule))
  /// Whole years from a table, made from ICU. Years are numbered from 0.
  Table(
    /// Chinese and Dangi, which have related years and a 60 year cycle.
    cyclic: Bool,
    /// The first day of each year, then the day after the last year.
    starts: HomogenousUnknownLengthTuple(Int),
    /// Each year's month shape.
    shapes: HomogenousUnknownLengthTuple(Int),
    /// Each shape: month numbers and their lengths in days.
    months: HomogenousUnknownLengthTuple(List(#(Int, Int))),
    /// Newest first.
    years: List(YearRule),
    /// Days that ICU calls day 0 of a month, as `#(day, month number)`.
    /// ICU's Chinese calendar makes a few of these, where its astronomy goes
    /// wrong.
    day_zero: List(#(Int, Int)),
  )
  NoMath
}

/// The Gregorian calendar's maths: AD from 1 January 1, and BC before.
/// Written here rather than generated, so Gregorian formatters load nothing
/// extra. `codegen/generate.ts` checks it against ICU.
pub const gregorian =
  Proleptic(
    [
      EraRule(start: -719_162, era: 0, base: 0, sign: 1),
      EraRule(start: -1_000_000_000_000, era: 1, base: 1, sign: -1),
    ],
  )

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
/// `year_start` and `next_year_start` are only set for table calendars, and
/// are both 0 otherwise.
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
