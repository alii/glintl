// Units of time, and offsets as Intl writes them.

export const MS_PER_SECOND = 1000;
export const SECONDS_PER_MINUTE = 60;
export const MINUTES_PER_HOUR = 60;
export const HOURS_PER_DAY = 24;
export const HOURS_PER_HALF_DAY = 12;
export const SECONDS_PER_HOUR = SECONDS_PER_MINUTE * MINUTES_PER_HOUR;
export const SECONDS_PER_DAY = SECONDS_PER_HOUR * HOURS_PER_DAY;
export const DAYS_PER_WEEK = 7;

// Numbers below this have one digit, and two digit years are the year modulo
// `TWO_DIGIT_YEARS`.
export const ONE_DIGIT_BELOW = 10;
export const TWO_DIGIT_YEARS = 100;

// Offsets write their hours and minutes with this many digits.
const OFFSET_DIGITS = 2;

// An offset in minutes as a time zone Intl accepts, like "+05:30".
export function offsetString(minutes: number): string {
  const sign = minutes < 0 ? "-" : "+";
  const abs = Math.abs(minutes);
  const pad = (n: number) => String(n).padStart(OFFSET_DIGITS, "0");

  return `${sign}${pad(Math.floor(abs / MINUTES_PER_HOUR))}:${pad(abs % MINUTES_PER_HOUR)}`;
}
