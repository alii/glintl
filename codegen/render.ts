// Renders patterns the way `src/glintl/internal/render.gleam` does, so the
// generator can check what it learned against ICU before writing it.

import { type CalendarDate, weekBasedYear } from "./calendars.ts";
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
    if (n < 0) return minus + number(-n, pad);
    return [...String(n).padStart(pad ? 2 : 1, "0")]
      .map((c) => digits[+c])
      .join("");
  };
  const hasMinute = tokens.some((t) => t.t === "minute");
  const hasSecond = tokens.some((t) => t.t === "second");
  const weekday = (((m.epochDay + 4) % 7) + 7) % 7;
  return tokens
    .map((token) => {
      switch (token.t) {
        case "literal":
          return token.value;
        case "ascii":
          return render([token.token], ASCII_DIGITS, m);
        case "year": {
          const year = m.date.year;
          if (token.twoDigit)
            return (
              (year < 0 ? token.minus : "") + number(Math.abs(year) % 100, true)
            );
          if (year === 1 && token.first) return token.first;
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
                ? h % 12
                : token.cycle === "h12"
                  ? h % 12 || 12
                  : h || 24;
          return number(shown, token.pad);
        }
        case "minute":
          return number(m.minute, token.pad);
        case "second":
          return number(m.second, token.pad);
        case "day_period": {
          const onTheHour =
            (!hasMinute || m.minute === 0) && (!hasSecond || m.second === 0);
          if (onTheHour && m.hour === 0) return token.midnight;
          if (onTheHour && m.hour === 12) return token.noon;
          return token.byHour[m.hour]!;
        }
        case "zone": {
          const offset = m.offsetMinutes;
          if (offset === 0 && m.unixSeconds >= 0) return token.zero;
          const negative = offset < 0;
          const abs = Math.abs(offset);
          const sign = negative ? token.negative : token.positive;
          const hours = number(Math.floor(abs / 60), token.padHours);
          if (abs % 60 === 0 && token.optionalMinutes)
            return (
              sign +
              hours +
              (negative ? token.negativeWholeSuffix : token.positiveWholeSuffix)
            );
          return (
            sign +
            hours +
            token.separator +
            number(abs % 60, true) +
            (negative ? token.negativeSuffix : token.positiveSuffix)
          );
        }
      }
    })
    .join("");
}
