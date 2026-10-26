// ICU's names for the calendars, by the name of each `glintl.Calendar`.
const CALENDARS = {
  Gregorian: "gregory",
  Iso8601: "iso8601",
  Buddhist: "buddhist",
  Japanese: "japanese",
  RepublicOfChina: "roc",
  Persian: "persian",
  Indian: "indian",
  Hebrew: "hebrew",
  Chinese: "chinese",
  Dangi: "dangi",
  Coptic: "coptic",
  Ethiopic: "ethiopic",
  EthiopicAmeteAlem: "ethioaa",
  IslamicCivil: "islamic-civil",
  IslamicTabular: "islamic-tbla",
  IslamicUmmAlQura: "islamic-umalqura",
};

// Gleam's custom types are classes, named after their constructors, so a
// `Full` style is "full" and a `DateOnly` is shown with only a date.
const style = (style) => style.constructor.name.toLowerCase();

export function compile(tag, _data, _calendars, calendar, shown) {
  const options = { calendar: CALENDARS[calendar.constructor.name] };
  switch (shown.constructor.name) {
    case "DateOnly":
      options.dateStyle = style(shown[0]);
      break;
    case "TimeOnly":
      options.timeStyle = style(shown[0]);
      break;
    case "DateAndTime":
      options.dateStyle = style(shown.date);
      options.timeStyle = style(shown.time);
      break;
  }
  return { tag, options, byOffset: new Map() };
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
