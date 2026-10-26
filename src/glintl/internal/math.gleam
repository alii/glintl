//// How each calendar maps days to its own dates, in the order of
//// `glintl.Calendar`. Each calendar but Gregorian is its own generated
//// Erlang module, so only the ones in use are loaded.

import glintl/internal/data.{type Math, NoMath}

pub fn math(calendar: Int) -> Math {
  case calendar {
    0 -> data.gregorian
    1 -> iso8601()
    2 -> buddhist()
    3 -> japanese()
    4 -> roc()
    5 -> persian()
    6 -> indian()
    7 -> hebrew()
    8 -> chinese()
    9 -> dangi()
    10 -> coptic()
    11 -> ethiopic()
    12 -> ethioaa()
    13 -> islamic_civil()
    14 -> islamic_tbla()
    _ -> islamic_umalqura()
  }
}

@external(erlang, "glintl_generated_calendar_iso8601", "math")
fn iso8601() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_buddhist", "math")
fn buddhist() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_japanese", "math")
fn japanese() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_roc", "math")
fn roc() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_persian", "math")
fn persian() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_indian", "math")
fn indian() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_hebrew", "math")
fn hebrew() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_chinese", "math")
fn chinese() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_dangi", "math")
fn dangi() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_coptic", "math")
fn coptic() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_ethiopic", "math")
fn ethiopic() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_ethioaa", "math")
fn ethioaa() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_islamic_civil", "math")
fn islamic_civil() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_islamic_tbla", "math")
fn islamic_tbla() -> Math {
  NoMath
}

@external(erlang, "glintl_generated_calendar_islamic_umalqura", "math")
fn islamic_umalqura() -> Math {
  NoMath
}
