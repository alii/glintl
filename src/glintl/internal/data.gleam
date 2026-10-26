//// `codegen/generate.ts` writes these as Erlang terms, so keep the two in
//// sync.

/// A locale's Gregorian formats.
pub type Data {
  Data(digits: Digits, gregorian: Formats)
}

pub type Digits {
  /// `0` to `9`.
  Ascii
  /// Ten strings, for zero to nine.
  Digits(List(String))
}

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

/// One of something for each style.
pub type Styles(a) {
  Styles(full: a, long: a, medium: a, short: a)
}

pub type Formats {
  Formats(
    dates: Styles(Pattern),
    times: Styles(Pattern),
    /// How each date style joins a date and a time.
    glues: Styles(Glue),
    eras: List(EraFormats),
  )
}

/// Date patterns for an era that ICU formats differently from the rest.
pub type EraFormats {
  EraFormats(era: Int, dates: Styles(Pattern), combined: Combined)
}

pub type Combined {
  /// The era's dates are joined to times by the usual glue.
  Joined
  /// ICU doesn't just join the era's dates and times, so each pair has its
  /// own pattern, by date style then time style.
  Combined(Styles(Styles(Pattern)))
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
  /// `first` is how year 1 is written when it isn't a number, like 元, and
  /// `minus_first` the same for year -1, which ICU 78.3's Japanese also
  /// writes as 元.
  Year(two_digit: Bool, minus: String, first: String, minus_first: String)
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
  /// Days before `julian_before` are in the Julian calendar, as ICU does by
  /// default for calendars other than Gregorian.
  Proleptic(eras: List(EraRule), julian_before: Int)
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

/// Stands in for the start of time: a day earlier than any glintl formats,
/// in days since 1970-01-01. The generator writes the same number.
pub const start_of_time = -1_000_000_000_000

/// 1 January AD 1, in days since 1970-01-01.
pub const first_day_of_ad = -719_162

/// The Gregorian calendar's eras, numbered newest first like generated eras.
const anno_domini = 0

const before_christ = 1

/// The Gregorian calendar's maths. AD years are astronomical years, and BC
/// years count back from 1 BC, which is astronomical year 0. Written here
/// rather than generated, so Gregorian formatters load nothing extra.
/// `codegen/generate.ts` checks it against ICU.
pub const gregorian =
  Proleptic(
    [
      EraRule(start: first_day_of_ad, era: anno_domini, base: 0, sign: 1),
      EraRule(start: start_of_time, era: before_christ, base: 1, sign: -1),
    ],
    julian_before: start_of_time,
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
