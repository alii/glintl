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

// An offset as Intl wants it, like "+05:30".
function offsetString(minutes) {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / MINUTES_PER_HOUR))}:${pad(abs % MINUTES_PER_HOUR)}`;
}
