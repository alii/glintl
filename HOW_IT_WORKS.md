# How glintl works

On JavaScript, glintl calls JavaScript's `Intl.DateTimeFormat` directly. No locale data is included on JavaScript so it's safe to include Glintl in size-sensitive programs, like for the browser.

On Erlang, we take the data from ICU when we build glintl and ship it inside the package, so your program never needs to download it or read it from disk. We store it as [literals](https://www.erlang.org/doc/system/eff_guide_processes.html#literal-pool), which Erlang keeps in one place for every process to share. We're still working on making it load faster.

If you're coming from Elixir, [Localize](https://github.com/elixir-localize/localize) does much more than glintl, like formatting numbers and units. This is planned to be added to Glintl, but until then the main difference is that Localize loads locale data from files or the network, and if a file is missing it quietly falls back to another locale. Glintl gives you a lookup function. It never falls back on an unknown locale, but it has helpers so you can do that yourself.
