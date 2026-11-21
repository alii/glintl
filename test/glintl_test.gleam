import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleeunit
import glintl
@target(erlang)
import glintl/calendar_fixtures
import glintl/date
import glintl/date_time
import glintl/field_fixtures
import glintl/fixtures
@target(erlang)
import glintl/internal/engine
@target(erlang)
import glintl/internal/render
import glintl/locale/en
import glintl/locale/en_gb
import glintl/locale/fa
import glintl/locale/ja
import glintl/locale/th
import glintl/locale/zh
import glintl/locales
import glintl/time_zone

pub fn main() -> Nil {
  gleeunit.main()
}

// --- The API -----------------------------------------------------------------

pub fn example_test() {
  let formatter =
    date_time.date_time_formatter(
      en_gb.locale(),
      date: date_time.Long,
      time: date_time.Short,
    )
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)
  assert date_time.format(formatter, moment, zone:)
    == "25 October 2026 at 23:40"
}

pub fn fields_example_test() {
  let formatter =
    date_time.new()
    |> date_time.weekday(glintl.Long)
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Long)
    |> date_time.fields_formatter(en_gb.locale(), _)
  let sunday = timestamp.from_unix_seconds(1_792_929_600)
  assert date_time.format(formatter, sunday, zone: time_zone.utc)
    == "Sunday 25 October"
}

/// These tests check the examples in the docs are correct.
pub fn doc_examples_test() {
  let assert Ok(now) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let assert Ok(summer) = timestamp.parse_rfc3339("2026-07-25T22:40:58Z")
  let assert Ok(plus_one) = time_zone.offset(hours: 1, minutes: 0)
  let utc = time_zone.utc
  // README
  assert date_time.new()
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Short)
    |> date_time.hour(glintl.TwoDigit)
    |> date_time.minute(glintl.TwoDigit)
    |> date_time.fields_formatter(en_gb.locale(), _)
    |> date_time.format(now, zone: plus_one)
    == "25 Oct, 23:40"
  // glintl
  assert en.locale()
    |> glintl.with_hour_cycle(glintl.H23)
    |> date_time.time_formatter(style: date_time.Short)
    |> date_time.format(now, zone: utc)
    == "22:40"
  assert en_gb.locale()
    |> glintl.with_calendar(glintl.hebrew)
    |> date_time.date_formatter(style: date_time.Long)
    |> date_time.format(now, zone: utc)
    == "14 Heshvan 5787"
  let assert Ok(latin) = glintl.numbering_system("latn")
  assert fa.locale()
    |> glintl.with_numbering_system(latin)
    |> date_time.date_formatter(style: date_time.Short)
    |> date_time.format(now, zone: utc)
    == "1405/8/3"
  assert glintl.calendar_from_name("hebrew") == Ok(glintl.hebrew)
  assert glintl.calendar_from_name("islamic") == Ok(glintl.islamic_tabular)
  assert glintl.calendar_name(glintl.hebrew) == "hebrew"
  assert glintl.locale_calendar(th.locale()) == glintl.buddhist
  assert glintl.locale_hour_cycle(en.locale()) == glintl.H12
  assert glintl.numbering_system("roman") == Error(Nil)
  assert glintl.locale_tag(en_gb.locale()) == "en-GB"
  let assert Ok(japanese) = locales.from_tag("ja-JP-u-ca-japanese")
  assert glintl.locale_tag(japanese) == "ja"
  // glintl/time_zone
  assert time_zone.from_name("Mars/Olympus_Mons") == Error(Nil)
  // glintl/date_time
  assert date_time.date_time_formatter(
      en_gb.locale(),
      date: date_time.Long,
      time: date_time.Short,
    )
    |> date_time.format(now, zone: plus_one)
    == "25 October 2026 at 23:40"
  let style = fn(formatter) { date_time.format(formatter, now, zone: plus_one) }
  assert list.map(
      [date_time.Full, date_time.Long, date_time.Medium, date_time.Short],
      fn(s) {
        #(
          style(date_time.date_formatter(en_gb.locale(), style: s)),
          style(date_time.time_formatter(en_gb.locale(), style: s)),
        )
      },
    )
    == [
      #("Sunday, 25 October 2026", "23:40:58 GMT+01:00"),
      #("25 October 2026", "23:40:58 GMT+1"),
      #("25 Oct 2026", "23:40:58"),
      #("25/10/2026", "23:40"),
    ]
  assert date_time.new()
    |> date_time.day(glintl.Numeric)
    |> date_time.month_name(glintl.Short)
    |> date_time.fields_formatter(en_gb.locale(), _)
    |> date_time.format(now, zone: utc)
    == "25 Oct"
  let long_parts = [
    date_time.Day("25"),
    date_time.Literal(" "),
    date_time.Month("October"),
    date_time.Literal(" "),
    date_time.Year("2026"),
  ]
  assert date_time.date_formatter(en_gb.locale(), style: date_time.Long)
    |> date_time.format_to_parts(now, zone: utc)
    == long_parts
  let assert Ok(london) = time_zone.from_name("Europe/London")
  let zone_name = fn(name, zone) {
    date_time.new()
    |> date_time.time_zone_name(name)
    |> date_time.hour(glintl.Numeric)
    |> date_time.fields_formatter(en_gb.locale(), _)
    |> date_time.format_to_parts(summer, zone:)
    |> list.find_map(fn(part) {
      case part {
        date_time.TimeZoneName(text) -> Ok(text)
        _ -> Error(Nil)
      }
    })
  }
  assert list.map(
      [
        date_time.ShortName,
        date_time.LongName,
        date_time.ShortOffset,
        date_time.LongOffset,
        date_time.ShortGeneric,
        date_time.LongGeneric,
      ],
      fn(name) { #(zone_name(name, london), zone_name(name, plus_one)) },
    )
    == [
      #(Ok("BST"), Ok("GMT+1")),
      #(Ok("British Summer Time"), Ok("GMT+01:00")),
      #(Ok("GMT+1"), Ok("GMT+1")),
      #(Ok("GMT+01:00"), Ok("GMT+01:00")),
      #(Ok("United Kingdom Time"), Ok("GMT+1")),
      #(Ok("British Time"), Ok("GMT+01:00")),
    ]
  let assert Ok(late) = timestamp.parse_rfc3339("2026-10-25T22:40:58.98Z")
  assert date_time.new()
    |> date_time.second(glintl.Numeric)
    |> date_time.fractional_second(date_time.Tenths)
    |> date_time.fields_formatter(en.locale(), _)
    |> date_time.format(late, zone: utc)
    == "58.9"
  let hour_and_words = fn(locale) {
    date_time.new()
    |> date_time.hour(glintl.Numeric)
    |> date_time.day_period(glintl.Long)
    |> date_time.fields_formatter(locale, _)
    |> date_time.format(now, zone: utc)
  }
  assert hour_and_words(en.locale()) == "10 at night"
  assert hour_and_words(en.locale() |> glintl.with_hour_cycle(glintl.H23))
    == "22"
  // glintl/date
  let day = calendar.Date(2026, calendar.October, 25)
  assert date.new()
    |> date.era(glintl.Short)
    |> date.fields_formatter(en.locale(), _)
    |> date.format(day)
    == "10/25/2026 AD"
  assert date.date_formatter(en_gb.locale(), style: date.Long)
    |> date.format(day)
    == "25 October 2026"
  assert list.map([date.Full, date.Long, date.Medium, date.Short], fn(s) {
      date.date_formatter(en_gb.locale(), style: s) |> date.format(day)
    })
    == [
      "Sunday, 25 October 2026",
      "25 October 2026",
      "25 Oct 2026",
      "25/10/2026",
    ]
  assert date.new()
    |> date.weekday(glintl.Long)
    |> date.day(glintl.Numeric)
    |> date.month_name(glintl.Long)
    |> date.fields_formatter(en_gb.locale(), _)
    |> date.format(day)
    == "Sunday 25 October"
  assert date.new()
    |> date.day(glintl.Numeric)
    |> date.month_name(glintl.Short)
    |> date.fields_formatter(en_gb.locale(), _)
    |> date.format(day)
    == "25 Oct"
  assert date.date_formatter(en_gb.locale(), style: date.Long)
    |> date.format_to_parts(day)
    == [
      date.Day("25"),
      date.Literal(" "),
      date.Month("October"),
      date.Literal(" "),
      date.Year("2026"),
    ]
  assert date.date_formatter(en_gb.locale(), style: date.Long)
    |> date.format(calendar.Date(2026, calendar.February, 31))
    == "3 March 2026"
}

pub fn parts_test() {
  let formatter =
    date_time.date_time_formatter(
      en_gb.locale(),
      date: date_time.Long,
      time: date_time.Short,
    )
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)
  let parts = date_time.format_to_parts(formatter, moment, zone:)
  assert parts
    == [
      date_time.Day("25"),
      date_time.Literal(" "),
      date_time.Month("October"),
      date_time.Literal(" "),
      date_time.Year("2026"),
      date_time.Literal(" at "),
      date_time.Hour("23"),
      date_time.Literal(":"),
      date_time.Minute("40"),
    ]
  assert string.concat(list.map(parts, date_time.part_text))
    == date_time.format(formatter, moment, zone:)
}

pub fn date_parts_test() {
  let formatter =
    date.new()
    |> date.year(glintl.Numeric)
    |> date.era(glintl.Short)
    |> date.fields_formatter(
      ja.locale() |> glintl.with_calendar(glintl.japanese),
      _,
    )
  assert date.format_to_parts(formatter, calendar.Date(2019, calendar.May, 1))
    == [date.Era("令和"), date.Year("元"), date.Literal("年")]
}

pub fn numbering_system_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-26T13:05:09Z")
  let short = fn(locale) {
    date_time.date_formatter(locale, style: date_time.Short)
    |> date_time.format(moment, zone: time_zone.utc)
  }
  let assert Ok(latin) = glintl.numbering_system("latn")
  let assert Ok(arabic) = glintl.numbering_system("ARAB")
  assert glintl.numbering_system_name(arabic) == "arab"
  assert glintl.numbering_system("roman") == Error(Nil)
  assert glintl.numbering_system_name(
      glintl.locale_numbering_system(fa.locale()),
    )
    == "arabext"
  assert short(fa.locale()) == "۱۴۰۵/۸/۴"
  // Persian months come from a table, so their digits change too.
  assert short(fa.locale() |> glintl.with_numbering_system(latin)) == "1405/8/4"
  assert short(en.locale() |> glintl.with_numbering_system(arabic))
    == "١٠/٢٦/٢٦"
  // ICU writes Japanese years with 年 in ASCII digits.
  let assert Ok(thai) = glintl.numbering_system("thai")
  assert ja.locale()
    |> glintl.with_calendar(glintl.japanese)
    |> glintl.with_numbering_system(thai)
    |> date_time.date_formatter(style: date_time.Full)
    |> date_time.format(moment, zone: time_zone.utc)
    == "令和8年๑๐月๒๖日月曜日"
  // Arabic digits have their own decimal separator.
  assert date_time.new()
    |> date_time.second(glintl.Numeric)
    |> date_time.fractional_second(date_time.Tenths)
    |> date_time.fields_formatter(
      en.locale() |> glintl.with_numbering_system(arabic),
      _,
    )
    |> date_time.format(moment, zone: time_zone.utc)
    == "٩٫٠"
}

pub fn tag_settings_test() {
  let assert Ok(japanese) = locales.from_tag("ja-JP-u-ca-japanese")
  assert glintl.locale_calendar(japanese) == glintl.japanese
  let assert Ok(clock) = locales.from_tag("en-u-hc-h23")
  assert glintl.locale_hour_cycle(clock) == glintl.H23
  let assert Ok(digits) = locales.from_tag("EN_u_nu_arab")
  assert glintl.numbering_system_name(glintl.locale_numbering_system(digits))
    == "arab"
  // Like Intl, it takes aliases and ignores values it doesn't know.
  let assert Ok(islamic) = locales.from_tag("en-u-ca-islamic-hc-h99")
  assert glintl.locale_calendar(islamic) == glintl.islamic_tabular
  assert glintl.locale_hour_cycle(islamic) == glintl.H12
  // Everything after -x- is private.
  let assert Ok(private) = locales.from_tag("en-x-u-ca-japanese")
  assert glintl.locale_calendar(private) == glintl.gregorian
  let assert Ok(negotiated) =
    locales.negotiate("en-AU-u-ca-buddhist", among: [en.locale()])
  assert glintl.locale_calendar(negotiated) == glintl.buddhist
}

/// Like Intl, a formatter with no date or time fields shows a numeric date.
pub fn default_fields_test() {
  let midday = timestamp.from_unix_seconds(1_792_929_600)
  let format = fn(fields) {
    date_time.fields_formatter(en_gb.locale(), fields)
    |> date_time.format(midday, zone: time_zone.utc)
  }
  assert format(date_time.new()) == "25/10/2026"
  assert format(date_time.new() |> date_time.era(glintl.Long))
    == "25/10/2026 Anno Domini"
}

pub fn fraction_test() {
  let formatter =
    date_time.new()
    |> date_time.second(glintl.Numeric)
    |> date_time.fractional_second(date_time.Hundredths)
    |> date_time.fields_formatter(en_gb.locale(), _)
  let moment =
    timestamp.from_unix_seconds(1_792_929_604)
    |> timestamp.add(duration.milliseconds(987))
  // glintl cuts fractions off instead of rounding them.
  assert date_time.format(formatter, moment, zone: time_zone.utc) == "4.98"
}

pub fn from_tag_test() {
  assert locales.from_tag("en_gb") |> result_tag == Ok("en-GB")
  assert locales.from_tag("EN-AU") |> result_tag == Ok("en-AU")
  assert locales.from_tag("en-XX") |> result_tag == Ok("en")
  assert locales.from_tag("zh-TW") |> result_tag == Ok("zh-Hant")
  assert locales.from_tag("fr-CA-x-mine") |> result_tag == Ok("fr-CA")
  assert locales.from_tag("as") |> result_tag == Ok("as")
  assert locales.from_tag("xx") == Error(Nil)
}

pub fn accept_language_test() {
  let tag = fn(result) { result |> result_tag }
  assert locales.from_accept_language("fr-CH, fr;q=0.9, en;q=0.8") |> tag
    == Ok("fr-CH")
  assert locales.from_accept_language("en;q=0.5, ja") |> tag == Ok("ja")
  assert locales.from_accept_language("xx, en-XX;q=0.1") |> tag == Ok("en")
  assert locales.from_accept_language("zh-TW") |> tag == Ok("zh-Hant")
  assert locales.from_accept_language("ja;q=0, *") == Error(Nil)
  assert locales.from_accept_language("") == Error(Nil)

  let supported = [en_gb.locale(), ja.locale(), zh.locale()]
  assert locales.negotiate("fr, en-AU;q=0.9", among: supported) |> tag
    == Ok("en-GB")
  assert locales.negotiate("ja-JP, en", among: supported) |> tag == Ok("ja")
  assert locales.negotiate("zh-TW", among: supported) |> tag == Ok("zh")
  assert locales.negotiate("de, fr", among: supported) == Error(Nil)
  let hebrew = glintl.with_calendar(en_gb.locale(), glintl.hebrew)
  assert locales.negotiate("en-GB", among: [hebrew]) == Ok(hebrew)
}

pub fn hour_cycle_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-26T22:40:00Z")
  let time = fn(locale) {
    date_time.time_formatter(locale, style: date_time.Short)
    |> date_time.format(moment, zone: time_zone.utc)
  }
  assert glintl.locale_hour_cycle(en_gb.locale()) == glintl.H23
  assert glintl.locale_hour_cycle(en.locale()) == glintl.H12
  assert en.locale() |> glintl.with_hour_cycle(glintl.H23) |> time == "22:40"
  assert en_gb.locale() |> glintl.with_hour_cycle(glintl.H12) |> time
    == "10:40 pm"
  assert ja.locale() |> glintl.with_hour_cycle(glintl.H12) |> time == "午後10:40"
  assert en_gb.locale()
    |> glintl.with_hour_cycle(glintl.H11)
    |> glintl.locale_hour_cycle
    == glintl.H11
  // Japanese writes the date differently next to a 12 hour time.
  assert ja.locale()
    |> glintl.with_hour_cycle(glintl.H12)
    |> date_time.date_time_formatter(
      date: date_time.Long,
      time: date_time.Short,
    )
    |> date_time.format(moment, zone: time_zone.utc)
    == "2026/10/26 午後10:40"
}

pub fn date_test() {
  let birthday = calendar.Date(2026, calendar.October, 26)
  let styled = fn(style) {
    date.date_formatter(en_gb.locale(), style:) |> date.format(birthday)
  }
  assert styled(date.Full) == "Monday, 26 October 2026"
  assert styled(date.Long) == "26 October 2026"
  assert styled(date.Medium) == "26 Oct 2026"
  assert styled(date.Short) == "26/10/2026"

  let options =
    date.new()
    |> date.weekday(glintl.Long)
    |> date.day(glintl.Numeric)
    |> date.month_name(glintl.Long)
  assert date.fields_formatter(en_gb.locale(), options) |> date.format(birthday)
    == "Monday 26 October"

  // Like Intl, an era on its own gets a numeric date.
  assert date.fields_formatter(
      en_gb.locale(),
      date.new() |> date.era(glintl.Long),
    )
    |> date.format(birthday)
    == "26/10/2026 Anno Domini"

  assert en_gb.locale()
    |> glintl.with_calendar(glintl.hebrew)
    |> date.date_formatter(style: date.Long)
    |> date.format(birthday)
    == "15 Heshvan 5787"
}

pub fn from_name_test() {
  assert time_zone.from_name("Europe/London") |> result.is_ok
  assert time_zone.from_name("europe/london")
    == time_zone.from_name("Europe/London")
  assert time_zone.from_name("GB") |> result.is_ok
  assert time_zone.from_name("UTC") |> result.is_ok
  assert time_zone.from_name("Nowhere/Special") == Error(Nil)
  assert time_zone.from_name("+01:00") == Error(Nil)
  assert time_zone.from_name("") == Error(Nil)
}

pub fn local_test() {
  assert time_zone.local() |> result.is_ok
}

@target(erlang)
/// On Erlang, `TZ` beats the system's settings. It can be a name or a path.
pub fn local_from_tz_test() {
  assert with_tz("Asia/Tokyo", time_zone.local)
    == time_zone.from_name("Asia/Tokyo")
  assert with_tz(":/usr/share/zoneinfo/Europe/Paris", time_zone.local)
    == time_zone.from_name("Europe/Paris")
  assert with_tz("Nowhere/Special", time_zone.local) == Error(Nil)
}

@target(erlang)
@external(erlang, "glintl_test_ffi", "with_tz")
fn with_tz(value: String, run: fn() -> a) -> a

/// Old local mean time offsets can include seconds.
pub fn named_zone_test() {
  let time = fn(zone_name, rfc3339) {
    let assert Ok(zone) = time_zone.from_name(zone_name)
    let assert Ok(moment) = timestamp.parse_rfc3339(rfc3339)
    date_time.time_formatter(en_gb.locale(), style: date_time.Medium)
    |> date_time.format(moment, zone:)
  }
  assert time("Europe/London", "2026-01-15T12:00:00Z") == "12:00:00"
  assert time("Europe/London", "2026-07-15T12:00:00Z") == "13:00:00"
  // The clocks go forward at 01:00 UTC on the last Sunday of March.
  assert time("Europe/London", "2026-03-29T00:59:59Z") == "00:59:59"
  assert time("Europe/London", "2026-03-29T01:00:00Z") == "02:00:00"
  assert time("Europe/London", "2100-07-15T12:00:00Z") == "13:00:00"
  assert time("Europe/London", "1800-06-01T12:00:00Z") == "11:58:45"
  assert time("Australia/Sydney", "2026-01-15T00:00:00Z") == "11:00:00"
  assert time("Australia/Sydney", "2026-07-15T00:00:00Z") == "10:00:00"
  assert time("Asia/Kolkata", "2026-07-15T00:00:00Z") == "05:30:00"
}

/// Fixed offsets and zones the locale has no name for show the offset.
pub fn zone_names_test() {
  let assert Ok(summer) = timestamp.parse_rfc3339("2026-07-15T12:00:00Z")
  let assert Ok(winter) = timestamp.parse_rfc3339("2026-01-15T12:00:00Z")
  let time = fn(locale, style, moment, name) {
    let assert Ok(zone) = time_zone.from_name(name)
    date_time.time_formatter(locale, style:)
    |> date_time.format(moment, zone:)
  }
  assert time(en_gb.locale(), date_time.Full, summer, "Europe/London")
    == "13:00:00 British Summer Time"
  assert time(en_gb.locale(), date_time.Long, summer, "Europe/London")
    == "13:00:00 BST"
  assert time(en_gb.locale(), date_time.Full, winter, "Africa/Abidjan")
    == "12:00:00 Greenwich Mean Time"
  // ICU 79.1 has no British English name for London in winter.
  assert time(en_gb.locale(), date_time.Full, winter, "Europe/London")
    == "12:00:00 GMT+00:00"
  assert time(en.locale(), date_time.Long, summer, "America/New_York")
    == "8:00:00 AM EDT"
  // English has no short name for Western European Time.
  assert time(en.locale(), date_time.Long, winter, "Europe/Lisbon")
    == "12:00:00 PM GMT+0"
  assert time(en_gb.locale(), date_time.Full, summer, "Etc/GMT-5")
    == "17:00:00 GMT+05:00"
  let assert Ok(plus_one) = time_zone.offset(hours: 1, minutes: 0)
  assert date_time.time_formatter(en_gb.locale(), style: date_time.Full)
    |> date_time.format(summer, zone: plus_one)
    == "13:00:00 GMT+01:00"
}

/// Intl only allows offsets under 24 hours either way.
pub fn offset_test() {
  assert time_zone.offset(hours: 5, minutes: 30) |> result.is_ok
  assert time_zone.offset(hours: -3, minutes: -30) |> result.is_ok
  assert time_zone.offset(hours: 23, minutes: 59) |> result.is_ok
  assert time_zone.offset(hours: -23, minutes: -59) |> result.is_ok
  assert time_zone.offset(hours: 24, minutes: 0)
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.offset(hours: -24, minutes: 0)
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.offset(hours: 1, minutes: 60)
    == Error(time_zone.MinutesTooLarge)
  assert time_zone.offset(hours: -3, minutes: 30) == Error(time_zone.MixedSigns)
  assert time_zone.from_duration(duration.hours(1)) == Ok(hours(1))
  assert time_zone.from_duration(duration.seconds(-1))
    == time_zone.offset(hours: 0, minutes: -1)
  assert time_zone.from_duration(duration.hours(24))
    == Error(time_zone.OffsetTooLarge)
  assert time_zone.from_duration(duration.hours(-25))
    == Error(time_zone.OffsetTooLarge)
}

/// Locales need to work as `Dict` keys on both targets.
pub fn locale_equality_test() {
  let hebrew = glintl.with_calendar(en_gb.locale(), glintl.hebrew)
  assert en_gb.locale() == en_gb.locale()
  assert locales.from_tag("en-GB") == Ok(en_gb.locale())
  assert hebrew == glintl.with_calendar(en_gb.locale(), glintl.hebrew)
  assert hebrew != en_gb.locale()
  assert en_gb.locale() != ja.locale()
}

pub fn calendar_test() {
  let assert Ok(moment) = timestamp.parse_rfc3339("2026-10-25T22:40:58Z")
  let format = fn(locale, moment) {
    date_time.date_formatter(locale, style: date_time.Long)
    |> date_time.format(moment, zone: hours(1))
  }
  assert glintl.locale_calendar(en_gb.locale()) == glintl.gregorian
  assert glintl.locale_calendar(th.locale()) == glintl.buddhist
  assert format(th.locale(), moment) == "25 ตุลาคม 2569"
  assert en_gb.locale()
    |> glintl.with_calendar(glintl.hebrew)
    |> format(moment)
    == "14 Heshvan 5787"
  let assert Ok(reiwa) = timestamp.parse_rfc3339("2019-05-01T12:00:00Z")
  assert ja.locale()
    |> glintl.with_calendar(glintl.japanese)
    |> format(reiwa)
    == "令和元年5月1日"
  let assert Ok(leap_month) = timestamp.parse_rfc3339("2025-08-01T12:00:00Z")
  assert zh.locale()
    |> glintl.with_calendar(glintl.chinese)
    |> format(leap_month)
    == "2025乙巳年闰六月8"
}

/// On Erlang, calendars with their own months only cover the years 1 to 4000.
/// Other days are written in the Gregorian calendar.
pub fn outside_calendar_tables_test() {
  let assert Ok(year_5000) = timestamp.parse_rfc3339("5000-01-01T12:00:00Z")
  let hebrew =
    en_gb.locale()
    |> glintl.with_calendar(glintl.hebrew)
    |> date_time.date_formatter(style: date_time.Long)
    |> date_time.format(year_5000, zone: time_zone.utc)
  let expected = case on_erlang() {
    True -> "1 January 5000"
    False -> "20 Kislev 8760"
  }
  assert hebrew == expected
}

// --- Generated fixtures --------------------------------------------------------
//
// The tests show only the first failures, because a broken pattern can fail
// thousands of cases at once.

/// Checks every locale, style and calendar against `Intl.DateTimeFormat`.
pub fn fixtures_test() {
  let failures =
    fixtures.cases()
    |> list.filter_map(fn(case_) {
      let #(tag, calendar, date, time, seconds, offset, expected) = case_
      let assert Ok(locale) = locales.from_tag(tag)
      let locale = case calendar {
        "" -> locale
        id -> glintl.with_calendar(locale, calendar_from_id(id))
      }
      let formatter = case date, time {
        0, time -> date_time.time_formatter(locale, style: style(time))
        date, 0 -> date_time.date_formatter(locale, style: style(date))
        date, time ->
          date_time.date_time_formatter(
            locale,
            date: style(date),
            time: style(time),
          )
      }
      let assert Ok(zone) = time_zone.from_duration(duration.minutes(offset))
      let actual =
        date_time.format(formatter, timestamp.from_unix_seconds(seconds), zone:)
      case actual == expected {
        True -> Error(Nil)
        False ->
          Ok(
            [tag, calendar]
            |> list.append(list.map(
              [date, time, seconds, offset],
              int.to_string,
            ))
            |> list.append([string.inspect(expected), string.inspect(actual)])
            |> string.join(" "),
          )
      }
    })
  assert list.take(failures, 30) == []
}

/// Checks fields in every locale and calendar against `Intl.DateTimeFormat`.
pub fn field_fixtures_test() {
  let failures =
    field_fixtures.cases()
    |> list.filter_map(fn(case_) {
      let #(
        tag,
        calendar,
        hour_cycle,
        shown,
        seconds,
        milliseconds,
        offset,
        expected,
      ) = case_
      let assert Ok(locale) = locales.from_tag(tag)
      let locale = case calendar {
        "" -> locale
        id -> glintl.with_calendar(locale, calendar_from_id(id))
      }
      let locale = case hour_cycle {
        "" -> locale
        "h11" -> glintl.with_hour_cycle(locale, glintl.H11)
        "h12" -> glintl.with_hour_cycle(locale, glintl.H12)
        "h23" -> glintl.with_hour_cycle(locale, glintl.H23)
        _ -> glintl.with_hour_cycle(locale, glintl.H24)
      }
      let formatter = date_time.fields_formatter(locale, parse_fields(shown))
      let assert Ok(zone) = time_zone.from_duration(duration.minutes(offset))
      let moment =
        timestamp.from_unix_seconds(seconds)
        |> timestamp.add(duration.milliseconds(milliseconds))
      let actual = date_time.format(formatter, moment, zone:)
      case actual == expected {
        True -> Error(Nil)
        False ->
          Ok(
            [tag, calendar, hour_cycle, shown]
            |> list.append(list.map(
              [seconds, milliseconds, offset],
              int.to_string,
            ))
            |> list.append([string.inspect(expected), string.inspect(actual)])
            |> string.join(" "),
          )
      }
    })
  assert list.take(failures, 30) == []
}

fn parse_fields(text: String) -> date_time.Fields {
  text
  |> string.split(",")
  |> list.fold(date_time.new(), fn(f, option) {
    let assert [name, value] = string.split(option, "=")
    case name, value {
      "weekday", _ -> date_time.weekday(f, width(value))
      "era", _ -> date_time.era(f, width(value))
      "year", _ -> date_time.year(f, digits(value))
      "month", "numeric" | "month", "2-digit" ->
        date_time.month(f, digits(value))
      "month", _ -> date_time.month_name(f, width(value))
      "day", _ -> date_time.day(f, digits(value))
      "dayPeriod", _ -> date_time.day_period(f, width(value))
      "hour", _ -> date_time.hour(f, digits(value))
      "minute", _ -> date_time.minute(f, digits(value))
      "second", _ -> date_time.second(f, digits(value))
      "fractionalSecondDigits", "1" ->
        date_time.fractional_second(f, date_time.Tenths)
      "fractionalSecondDigits", "2" ->
        date_time.fractional_second(f, date_time.Hundredths)
      "fractionalSecondDigits", _ ->
        date_time.fractional_second(f, date_time.Thousandths)
      "timeZoneName", "short" ->
        date_time.time_zone_name(f, date_time.ShortName)
      "timeZoneName", "long" -> date_time.time_zone_name(f, date_time.LongName)
      "timeZoneName", "shortOffset" ->
        date_time.time_zone_name(f, date_time.ShortOffset)
      "timeZoneName", "shortGeneric" ->
        date_time.time_zone_name(f, date_time.ShortGeneric)
      "timeZoneName", "longGeneric" ->
        date_time.time_zone_name(f, date_time.LongGeneric)
      "timeZoneName", _ -> date_time.time_zone_name(f, date_time.LongOffset)
      _, _ -> panic as { "unknown field in the fixtures: " <> name }
    }
  })
}

fn width(value: String) -> glintl.Width {
  case value {
    "narrow" -> glintl.Narrow
    "short" -> glintl.Short
    _ -> glintl.Long
  }
}

fn digits(value: String) -> glintl.Digits {
  case value {
    "numeric" -> glintl.Numeric
    _ -> glintl.TwoDigit
  }
}

@target(erlang)
/// JavaScript uses Intl for calendar maths, so only Erlang needs this.
pub fn calendar_fields_test() {
  let failures =
    calendar_fixtures.cases()
    |> list.filter(fn(case_) {
      let #(calendar, day, expected) = case_
      render.calendar_fields(
        engine.calendar_math(calendar_from_id(calendar))(),
        day,
      )
      != expected
    })
  assert list.take(failures, 30) == []
}

// --- Helpers -------------------------------------------------------------------

fn hours(hours: Int) -> time_zone.TimeZone {
  let assert Ok(zone) = time_zone.offset(hours:, minutes: 0)
  zone
}

@external(erlang, "glintl_test_ffi", "on_erlang")
@external(javascript, "./glintl_test_ffi.mjs", "on_erlang")
fn on_erlang() -> Bool

fn result_tag(result: Result(glintl.Locale, Nil)) -> Result(String, Nil) {
  case result {
    Ok(locale) -> Ok(glintl.locale_tag(locale))
    Error(Nil) -> Error(Nil)
  }
}

fn calendar_from_id(id: String) -> glintl.Calendar {
  case glintl.calendar_from_name(id) {
    Ok(calendar) -> calendar
    Error(Nil) -> panic as { "unknown calendar in the fixtures: " <> id }
  }
}

/// Fixtures number styles from 1 for full to 4 for short.
fn style(index: Int) -> date_time.Style {
  case index {
    1 -> date_time.Full
    2 -> date_time.Long
    3 -> date_time.Medium
    4 -> date_time.Short
    _ -> panic as { "unknown style in the fixtures: " <> int.to_string(index) }
  }
}
