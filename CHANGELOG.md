# Changelog

## 1.0.0

glintl formats dates and times in many languages, on Erlang and JavaScript. On Erlang, it gives the same output as JavaScript's `Intl`.

With glintl 1.0, you can:

- Format dates and times in 662 locales, in a ready-made style or with only the parts you pick.
- Style each part on its own with `format_to_parts`, like `Intl`'s `formatToParts`.
- Show a time in any time zone.
- Show which time zone a time is in, like "23:40 BST".
- Use other calendars, hour cycles and digits, like the Japanese calendar or a 24 hour clock.
- Pick each user's locale from a tag or an `Accept-Language` header

New formatters, like plural rules and numbers, will come in future 1.x releases
