//// Measures how much formatting allocates and how long it takes. Memory is
//// only measured on Erlang.
////
////   gleam run -m glintl_bench

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/time/timestamp.{type Timestamp}
import glintl
import glintl/date_time
import glintl/locale/en_gb
import glintl/time_zone

/// The first date is 14 November 2023, and the rest follow a week apart.
const first_date = 1_700_000_000

const seconds_per_week = 604_800

const dates_per_run = 90

/// How many runs to time, because one run is too quick to time well.
const timed_runs = 100

const microseconds_per_millisecond = 1000.0

const bytes_per_kilobyte = 1024

const decimal_places = 3

pub fn main() -> Nil {
  let #(first, first_time) = measure(fn() { format_dates(1) })
  let #(again, again_time) = measure(fn() { format_dates(1) })
  let #(make, _) =
    measure(fn() {
      formatter()
      Nil
    })
  let #(_, many_time) = measure(fn() { format_dates(timed_runs) })
  io.println(
    "first "
    <> int.to_string(dates_per_run)
    <> " dates: "
    <> kb(first)
    <> ", "
    <> ms(first_time),
  )
  io.println(
    "next "
    <> int.to_string(dates_per_run)
    <> " dates: "
    <> kb(again)
    <> ", "
    <> ms(again_time),
  )
  io.println("make a formatter: " <> kb(make))
  let #(make_fields, _) =
    measure(fn() {
      fields_formatter()
      Nil
    })
  let #(_, make_fields_time) =
    measure(fn() {
      int.range(from: 0, to: timed_runs, with: Nil, run: fn(_, _) {
        fields_formatter()
        Nil
      })
    })
  let #(_, fields_time) =
    measure(fn() { format_dates_with(fields_formatter(), timed_runs) })
  io.println(
    "make a fields formatter: "
    <> kb(make_fields)
    <> ", "
    <> per(make_fields_time, timed_runs),
  )
  io.println(
    "per date with fields, over "
    <> int.to_string(timed_runs * dates_per_run)
    <> ": "
    <> per(fields_time, timed_runs * dates_per_run),
  )
  io.println(
    "per date, over "
    <> int.to_string(timed_runs * dates_per_run)
    <> ": "
    <> float.to_string(float.to_precision(
      int.to_float(many_time) /. int.to_float(timed_runs * dates_per_run),
      decimal_places,
    ))
    <> " µs",
  )
}

fn formatter() -> date_time.Formatter {
  date_time.date_time_formatter(
    en_gb.locale(),
    date: date_time.Long,
    time: date_time.Short,
  )
}

/// Shows the same fields as `formatter`, so the two timings compare like with
/// like.
fn fields_formatter() -> date_time.Formatter {
  date_time.new()
  |> date_time.day(glintl.Numeric)
  |> date_time.month_name(glintl.Long)
  |> date_time.year(glintl.Numeric)
  |> date_time.hour(glintl.TwoDigit)
  |> date_time.minute(glintl.TwoDigit)
  |> date_time.fields_formatter(en_gb.locale(), _)
}

fn per(micros: Int, count: Int) -> String {
  float.to_string(float.to_precision(
    int.to_float(micros) /. int.to_float(count),
    decimal_places,
  ))
  <> " µs"
}

/// Formats the dates, `times` times over, with one formatter.
fn format_dates(times: Int) -> Nil {
  format_dates_with(formatter(), times)
}

fn format_dates_with(formatter: date_time.Formatter, times: Int) -> Nil {
  let dates = dates()
  let assert Ok(zone) = time_zone.offset(hours: 1, minutes: 0)
  int.range(from: 0, to: times, with: Nil, run: fn(_, _) {
    list.each(dates, fn(date) { date_time.format(formatter, date, zone:) })
  })
}

fn dates() -> List(Timestamp) {
  int.range(from: 0, to: dates_per_run, with: [], run: fn(acc, i) {
    [timestamp.from_unix_seconds(first_date + i * seconds_per_week), ..acc]
  })
}

fn ms(micros: Int) -> String {
  float.to_string(int.to_float(micros) /. microseconds_per_millisecond) <> " ms"
}

fn kb(bytes: Int) -> String {
  int.to_string(bytes / bytes_per_kilobyte) <> " KB"
}

@external(erlang, "glintl_bench_ffi", "measure")
@external(javascript, "./glintl_bench_ffi.mjs", "measure")
fn measure(f: fn() -> Nil) -> #(Int, Int)
