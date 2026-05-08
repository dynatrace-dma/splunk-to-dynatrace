# tests/

Regression tests for the v4.6.6 hardening work.

## Layout

| Dir | Purpose |
|---|---|
| `.bats/` | Vendored [bats-core](https://github.com/bats-core/bats-core) v1.10.0. Do not edit. |
| `baselines/` | Snapshots of current-code behavior captured **before** any v4.6.6 change. Diff-against-baseline is the regression detector. Committed. |
| `fixtures/` | REST-response fixtures. Anonymized real-customer data + programmatically synthesized data. Committed. Raw customer data is `.gitignore`d. |
| `unit/` | bats-core unit tests. Source the production script via `helpers.bash` with `main` stubbed. |
| `replay/` | Fixture-replay harness. Runs the same fixture through old + new code, byte-diffs the per-app outputs. |
| `perf/` | Wall-clock + bytes measurements. CSV results in `perf/results/`. |
| `live/` | Smoke tests requiring live access against a real archive. Manual gate, not run automatically. |

## Running

```bash
# All unit tests
.bats/bin/bats unit/

# Single file
.bats/bin/bats unit/test_collect_alerts.bats

# Replay harness against a fixture
replay/run_replay.sh fixtures/saved_searches_small.json

# Re-capture baselines after any change (then `git diff` to see what shifted)
baselines/recapture.sh
```

## When to run

| Trigger | Required tests |
|---|---|
| Before merging any v4.6.6 PR | `unit/` + `replay/run_replay.sh` against all fixtures + baseline diff is empty (or expected) |
| Before tagging the v4.6.6 release | All of the above + `live/` dry-run against a real archive |
| Routine local dev | `unit/` for the function you're touching |

## Adding a new test

1. Drop a `.bats` file under `unit/` named `test_<feature>.bats`.
2. `load helpers` at the top — gives you a sourced production script with `main` stubbed.
3. Write `@test "name" { ... }` blocks.
4. Run with `.bats/bin/bats unit/test_<feature>.bats`.

## Adding a new fixture

- **Synthetic**: edit `fixtures/generate.sh`, regenerate, commit the output.
- **Anonymized real**: pull raw via AZ CLI to a `.gitignore`d local path, run `fixtures/anonymize.sh`, commit only the anonymized output.
