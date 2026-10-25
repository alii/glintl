const STYLES = [undefined, "full", "long", "medium", "short"];

export function compile(tag, _data, date, time) {
  const options = { calendar: "gregory" };
  if (date) options.dateStyle = STYLES[date];
  if (time) options.timeStyle = STYLES[time];
  return { tag, options, byOffset: new Map() };
}

export function format(compiled, seconds, nanoseconds, offsetMinutes) {
  let formatter = compiled.byOffset.get(offsetMinutes);
  if (formatter === undefined) {
    formatter = new Intl.DateTimeFormat(compiled.tag, {
      ...compiled.options,
      timeZone: offsetString(offsetMinutes),
    });
    compiled.byOffset.set(offsetMinutes, formatter);
  }
  return formatter.format(seconds * 1000 + Math.floor(nanoseconds / 1e6));
}

function offsetString(minutes) {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n) => String(n).padStart(2, "0");
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}
