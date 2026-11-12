# Limits

- On Erlang, calendars with their own months only work from year 1 to 4000. Other years fall back to the Gregorian calendar.
- glintl on Erlang uses the ICU bundled at Glintl's own build time, but JavaScript uses ICU built into the runtime. Differences in ICU versions mean the two targets can disagree on small things, often in spaces and commas.
- ICU 78.3 puts Chinese New Year 2027 and 2030 a day off. JavaScript gets this wrong too, so we intentionally match it in the name of behaviour parity.
- Around midnight near AD 284 and AD 622, ICU shows the wrong year in the Coptic and Islamic calendars. We don't copy this bug yet, so glintl and JavaScript can disagree there.
