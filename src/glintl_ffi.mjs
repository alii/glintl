// @ts-check

import { Error as GleamError, Ok } from "./gleam.mjs";

/**
 * A `matcher.Request`. Each field is an Intl option, or "" or 0 to leave it out.
 * @typedef {object} Request
 * @property {string} weekday
 * @property {string} era
 * @property {string} year
 * @property {string} month
 * @property {string} day
 * @property {string} day_period
 * @property {string} hour
 * @property {string} minute
 * @property {string} second
 * @property {number} fractional_second_digits
 * @property {string} time_zone_name
 * @property {string} hour_cycle
 */

/**
 * An `engine.Compiled`, which keeps one `Intl.DateTimeFormat` per time zone.
 * @typedef {object} Compiled
 * @property {string} tag
 * @property {Record<string, string | number>} options Built from Gleam strings, so
 *   TypeScript can't see they're valid Intl options.
 * @property {Map<string, Intl.DateTimeFormat>} byZone
 */

/**
 * @param {string} tag
 * @param {string} calendar
 * @param {string} dateStyle
 * @param {string} timeStyle
 * @param {string} hourCycle
 * @returns {Compiled}
 */
export function formatter(tag, calendar, dateStyle, timeStyle, hourCycle) {
  /** @type {Compiled["options"]} */
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
  return { tag, options, byZone: new Map() };
}

/**
 * @param {string} tag
 * @param {string} calendar
 * @param {Request} request
 * @returns {Compiled}
 */
export function fieldsFormatter(tag, calendar, request) {
  /** @type {Compiled["options"]} */
  const options = { calendar };
  if (request.weekday !== "") options.weekday = request.weekday;
  if (request.era !== "") options.era = request.era;
  if (request.year !== "") options.year = request.year;
  if (request.month !== "") options.month = request.month;
  if (request.day !== "") options.day = request.day;
  if (request.day_period !== "") options.dayPeriod = request.day_period;
  if (request.hour !== "") options.hour = request.hour;
  if (request.minute !== "") options.minute = request.minute;
  if (request.second !== "") options.second = request.second;
  if (request.fractional_second_digits !== 0)
    options.fractionalSecondDigits = request.fractional_second_digits;
  if (request.time_zone_name !== "")
    options.timeZoneName = request.time_zone_name;
  if (request.hour_cycle !== "") options.hourCycle = request.hour_cycle;
  return { tag, options, byZone: new Map() };
}

/**
 * The locale's own hour cycle, which Intl only gives when showing a time.
 * @param {string} tag
 * @param {string} calendar
 * @returns {string}
 */
export function hourCycle(tag, calendar) {
  return /** @type {string} */ (
    new Intl.DateTimeFormat(tag, {
      calendar,
      timeStyle: "short",
    }).resolvedOptions().hourCycle
  );
}

const MILLISECONDS_PER_SECOND = 1000;
const NANOSECONDS_PER_MILLISECOND = 1_000_000;

/**
 * @param {Compiled} compiled
 * @param {number} seconds
 * @param {number} nanoseconds
 * @param {string} timeZone Intl's `timeZone` option, like "Europe/London" or "+05:30".
 * @returns {string}
 */
export function format(compiled, seconds, nanoseconds, timeZone) {
  let formatter = compiled.byZone.get(timeZone);
  if (formatter === undefined) {
    formatter = new Intl.DateTimeFormat(
      compiled.tag,
      /** @type {Intl.DateTimeFormatOptions} */ ({
        ...compiled.options,
        timeZone,
      }),
    );
    compiled.byZone.set(timeZone, formatter);
  }
  return formatter.format(
    seconds * MILLISECONDS_PER_SECOND +
      Math.floor(nanoseconds / NANOSECONDS_PER_MILLISECOND),
  );
}

/**
 * Intl's own spelling of a time zone name, or an error if Intl doesn't know it.
 * @param {string} name
 * @returns {Ok | GleamError}
 */
export function timeZoneName(name) {
  try {
    return new Ok(
      new Intl.DateTimeFormat("en", { timeZone: name }).resolvedOptions()
        .timeZone,
    );
  } catch {
    return new GleamError(undefined);
  }
}

/**
 * The time zone Intl uses by default.
 * @returns {Ok | GleamError}
 */
export function localTimeZone() {
  const zone = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  return zone ? new Ok(zone) : new GleamError(undefined);
}
