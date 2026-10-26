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
  let #(_, many_time) = measure(fn() { format_dates(100) })
  io.println("first 90 dates: " <> kb(first) <> ", " <> ms(first_time))
  io.println("next 90 dates: " <> kb(again) <> ", " <> ms(again_time))
  io.println("make a formatter: " <> kb(make))
  io.println(
    "per date, over 9000: "
    <> float.to_string(float.to_precision(int.to_float(many_time) /. 9000.0, 3))
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

/// Formats 90 dates, `times` times over, with one formatter.
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
  int.range(from: 0, to: 90, with: [], run: fn(acc, i) {
    [timestamp.from_unix_seconds(1_700_000_000 + i * 604_800), ..acc]
  })
}

fn ms(micros: Int) -> String {
  float.to_string(int.to_float(micros) /. 1000.0) <> " ms"
}

fn kb(bytes: Int) -> String {
  int.to_string(bytes / 1024) <> " KB"
}

@external(erlang, "glintl_bench_ffi", "measure")
@external(javascript, "./glintl_bench_ffi.mjs", "measure")
fn measure(f: fn() -> Nil) -> #(Int, Int)

@external(erlang, "glintl_bench_ffi", "code_bytes")
@external(javascript, "./glintl_bench_ffi.mjs", "code_bytes")
fn code_bytes() -> Int
