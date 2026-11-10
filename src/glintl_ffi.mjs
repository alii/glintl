export function formatter(tag, calendar, dateStyle, timeStyle, hourCycle) {
  const options = { calendar };
  if (dateStyle !== "") {
    options.dateStyle = dateStyle;
  }
  if (timeStyle !== "") {
    options.timeStyle = timeStyle;
  }
  if (hourCycle !== "") {
    options.hourCycle = hourCycle;
  }
  return { tag, options, byOffset: new Map() };
}

// `request` is a `matcher.Request`, whose fields are Intl's options, or "" or
// 0 when not shown.
export function fieldsFormatter(tag, calendar, request) {
  const options = { calendar };
  const set = (name, value) => {
    if (value !== "" && value !== 0) {
      options[name] = value;
    }
  };
  set("weekday", request.weekday);
  set("era", request.era);
  set("year", request.year);
  set("month", request.month);
  set("day", request.day);
  set("dayPeriod", request.day_period);
  set("hour", request.hour);
  set("minute", request.minute);
  set("second", request.second);
  set("fractionalSecondDigits", request.fractional_second_digits);
  set("timeZoneName", request.time_zone_name);
  set("hourCycle", request.hour_cycle);
  return { tag, options, byOffset: new Map() };
}

// The locale's own hour cycle, which Intl only gives when showing a time.
export function hourCycle(tag, calendar) {
  return new Intl.DateTimeFormat(tag, {
    calendar,
    timeStyle: "short",
  }).resolvedOptions().hourCycle;
}

const MILLISECONDS_PER_SECOND = 1000;
const NANOSECONDS_PER_MILLISECOND = 1_000_000;
const MINUTES_PER_HOUR = 60;

export function format(compiled, seconds, nanoseconds, offsetMinutes) {
  let formatter = compiled.byOffset.get(offsetMinutes);
  if (formatter === undefined) {
    formatter = new Intl.DateTimeFormat(compiled.tag, {
      ...compiled.options,
      timeZone: offsetString(offsetMinutes),
    });
    compiled.byOffset.set(offsetMinutes, formatter);
  }
  return formatter.format(
    seconds * MILLISECONDS_PER_SECOND +
      Math.floor(nanoseconds / NANOSECONDS_PER_MILLISECOND),
  );
}

// Writes an offset in minutes as a time zone Intl takes, like "+05:30".
function offsetString(minutes) {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / MINUTES_PER_HOUR))}:${pad(abs % MINUTES_PER_HOUR)}`;
}
