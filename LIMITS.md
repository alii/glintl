# Limits

- On Erlang, calendars with their own months cover the years 1 to 4000. glintl writes other years in the Gregorian calendar.
- On Erlang, glintl uses the ICU we built it with. On JavaScript, it uses the runtime's ICU. When the two versions differ, the targets can disagree on small details, often spaces and commas.
- ICU 78.3 puts Chinese New Year 2027 and 2030 a day off. JavaScript gets this wrong too, so we intentionally match it in the name of behaviour parity.
- Around midnight near AD 284 and AD 622, ICU shows the wrong year in the Coptic and Islamic calendars. glintl shows the right year there for now, so glintl and JavaScript can disagree.
