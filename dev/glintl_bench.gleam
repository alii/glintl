//// Measures how much formatting allocates and how long it takes. Memory is
//// only measured on Erlang.
////
////   gleam run -m glintl_bench

import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import glintl
import glintl/locale/en_gb

/// Dates are a week apart, from 14 November 2023.
const first_date = 1_700_000_000

const seconds_per_week = 604_800

const dates_per_run = 90

/// Runs to time, as one run of 90 is too quick to time well.
const timed_runs = 100

const microseconds_per_millisecond = 1000.0

const bytes_per_kilobyte = 1024

const decimal_places = 3

pub fn main() -> Nil {
  let code = code_bytes()
  let #(first, first_time) = measure(fn() { format_dates(1) })
  let loaded = code_bytes() - code
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
  io.println("code loaded: " <> kb(loaded))
}

fn formatter() -> glintl.Formatter {
  glintl.date_time_formatter(
    en_gb.locale(),
    date: glintl.Long,
    time: glintl.Short,
  )
}

/// Formats the dates, `times` times over, with one formatter.
fn format_dates(times: Int) -> Nil {
  let formatter = formatter()
  let dates = dates()
  int.range(from: 0, to: times, with: Nil, run: fn(_, _) {
    list.each(dates, fn(date) {
      glintl.format(formatter, date, offset: duration.hours(1))
    })
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

@external(erlang, "glintl_bench_ffi", "code_bytes")
@external(javascript, "./glintl_bench_ffi.mjs", "code_bytes")
fn code_bytes() -> Int
