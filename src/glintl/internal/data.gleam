//// `codegen/generate.ts` writes these as Erlang terms, so keep the two in
//// sync.

/// `NoData` on JavaScript, where `Intl.DateTimeFormat` is used.
pub type Data {
  Data(digits: Digits, patterns: List(Pattern))
  NoData
}

pub type Digits {
  /// `0` to `9`.
  Ascii
  /// Ten strings, for zero to nine.
  Digits(List(String))
}

pub type Pattern =
  List(Token)

pub type Token {
  Literal(String)
  Year(two_digit: Bool)
  MonthNumber(pad: Bool)
  /// Twelve names, January first.
  MonthName(names: List(String))
  Day(pad: Bool)
  /// Seven names, Sunday first.
  Weekday(names: List(String))
  Hour(pad: Bool, cycle: HourCycle)
  Minute(pad: Bool)
  Second(pad: Bool)
  /// One name per hour. Some locales have special words for exactly
  /// midnight and noon.
  DayPeriod(by_hour: List(String), midnight: String, noon: String)
  Era(bc: String, ad: String)
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
