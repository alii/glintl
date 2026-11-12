# Contributing

glintl has two parts. The Gleam library is in `src/`. The generator in `codegen/` runs on Bun. It reads ICU's data, then writes each locale's data and the test fixtures. Many changes touch both.

## Setting up

Install the generator's tools:

```sh
bun install --cwd codegen
```

## Before you push

Format, lint and type check the generator:

```sh
bun fmt --cwd codegen && bun lint --cwd codegen && bun check --cwd codegen
```

Format the Gleam code, then run the tests on both targets:

```sh
gleam format src test dev
gleam test --target erlang
gleam test --target javascript
```

On JavaScript, glintl calls `Intl`, so the JavaScript tests need the pinned Bun, described below.

## Bun version

The generated data comes from one Bun's ICU. The generator, the JavaScript tests and the checks against Intl all need that exact Bun, on Linux. The `.bun-image` file pins the specific version:

- The first line is a Docker image, by digest.
- The second line is the build of Bun inside the image.

CI copies Bun out of that image.

On a Mac, run the generator in Docker, then format what it wrote:

```sh
docker run --rm -v "$PWD":/repo -w /repo $(head -n1 .bun-image) bun codegen/generate.ts
gleam format src test
```

The generator takes a few minutes. It rewrites `src/glintl/locale/`, `src/glintl/internal/generated/` and the fixtures in `test/glintl/`. When your change only affects time zones, run `bun codegen/zones.ts` instead. It rewrites the time zone data in a few seconds.

## Checking against Intl

The conformance script formats a million random cases on Erlang and compares each one with `Intl.DateTimeFormat`:

```sh
bun codegen/conformance.ts 1000000
```

The script needs the pinned Bun and Erlang on the same machine. It also has these modes:

- `--every ja@japanese` tries every mix of fields in every hour cycle, for one locale and calendar. Add a part, like `3/16`, to split the work between several runs.
- `--zones` tries every time zone at each change of offset, with zone names in many locales.
- `--save cases.tsv`, then `--check cases.tsv`, is for when the pinned Bun and Erlang are on different machines. Save the cases where the pinned Bun is, then check them where Erlang is.

## Benchmark

The benchmark measures memory and speed on Erlang. Run it before and after a change that could make glintl slower or bigger:

```sh
gleam run -m glintl_bench
```
