// Renders patterns the way `src/glintl/internal/render.gleam` does, so the
// generator can check what it learned against ICU before writing it.

import { type CalendarDate, isoWeekday, weekBasedYear } from "./calendars.ts";
import {
  DAYS_PER_WEEK,
  HOURS_PER_DAY,
  HOURS_PER_HALF_DAY,
  MINUTES_PER_HOUR,
  ONE_DIGIT_BELOW,
  TWO_DIGIT_YEARS,
} from "./time.ts";
import type { GluePiece, Token } from "./patterns.ts";

export type Moment = {
  epochDay: number;
  date: CalendarDate;
  hour: number;
  minute: number;
  second: number;
  offsetMinutes: number;
  unixSeconds: number;
};

export function join(date: Token[], glue: GluePiece[], time: Token[]): Token[] {
  return glue.flatMap((piece): Token[] =>
    piece.t === "text"
      ? [{ t: "literal", value: piece.value }]
      : piece.t === "date"
        ? date
        : time,
  );
}

const ASCII_DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"];

export function render(tokens: Token[], digits: string[], m: Moment): string {
  const number = (n: number, pad: boolean, minus = "-"): string => {
    if (n < 0) {
      return minus + number(-n, pad);
    }
    return [...(pad && n < ONE_DIGIT_BELOW ? `0${n}` : String(n))]
      .map((c) => digits[+c])
      .join("");
  };
  const hasMinute = tokens.some((t) => t.t === "minute");
  const hasSecond = tokens.some((t) => t.t === "second");
  // From 0 for Sunday, as weekday names are.
  const weekday = isoWeekday(m.epochDay) % DAYS_PER_WEEK;
  return tokens
    .map((token) => {
      switch (token.t) {
        case "literal":
          return token.value;
        case "ascii":
          return render([token.token], ASCII_DIGITS, m);
        case "year": {
          const year = m.date.year;
          if (token.twoDigit) {
            return (
              (year < 0 ? token.minus : "") +
              number(Math.abs(year) % TWO_DIGIT_YEARS, true)
            );
          }
          if (year === 1 && token.first) {
            return token.first;
          }
          if (year === -1 && token.minusFirst) {
            return token.minusFirst;
          }
          return number(year, false, token.minus);
        }
        case "week_year":
          return number(
            weekBasedYear(
              m.date,
              m.epochDay,
              token.firstDay,
              token.minimalDays,
              token.exceptions,
            ),
            false,
            token.minus,
          );
        case "extended_year":
          return number(m.date.extended, false, token.minus);
        case "related_year":
          return number(m.date.related, false);
        case "year_name":
          return token.names[m.date.cycle]!;
        case "month_number":
          return number(m.date.month + 1, token.pad);
        case "month_name":
          return token.names[m.date.month]!;
        case "day":
          return number(m.date.day, token.pad);
        case "day_name":
          return token.names[m.date.day]!;
        case "weekday":
          return token.names[weekday]!;
        case "era":
          return token.names[m.date.era]!;
        case "hour": {
          const h = m.hour;
          const shown =
            token.cycle === "h23"
              ? h
              : token.cycle === "h11"
                ? h % HOURS_PER_HALF_DAY
                : token.cycle === "h12"
                  ? h % HOURS_PER_HALF_DAY || HOURS_PER_HALF_DAY
                  : h || HOURS_PER_DAY;
          return number(shown, token.pad);
        }
        case "minute":
          return number(m.minute, token.pad);
        case "second":
          return number(m.second, token.pad);
        case "day_period": {
          const onTheHour =
            (!hasMinute || m.minute === 0) && (!hasSecond || m.second === 0);
          if (onTheHour && m.hour === 0) {
            return token.midnight;
          }
          if (onTheHour && m.hour === HOURS_PER_HALF_DAY) {
            return token.noon;
          }
          return token.byHour[m.hour]!;
        }
        case "zone": {
          const offset = m.offsetMinutes;
          if (offset === 0 && m.unixSeconds >= 0) {
            return token.zero;
          }
          const negative = offset < 0;
          const abs = Math.abs(offset);
          const sign = negative ? token.negative : token.positive;
          const hours = number(
            Math.floor(abs / MINUTES_PER_HOUR),
            token.padHours,
          );
          if (abs % MINUTES_PER_HOUR === 0 && token.optionalMinutes) {
            return (
              sign +
              hours +
              (negative ? token.negativeWholeSuffix : token.positiveWholeSuffix)
            );
          }
          return (
            sign +
            hours +
            token.separator +
            number(abs % MINUTES_PER_HOUR, true) +
            (negative ? token.negativeSuffix : token.positiveSuffix)
          );
        }
      }
    })
    .join("");
}
