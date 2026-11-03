## What changed

## Why

## How it was checked
- [ ] `dbt build` passes (or CI is green)
- [ ] `dbt build --select package:dbt_project_evaluator` is clean
- [ ] New or changed models have descriptions and tests
- [ ] If an incremental model changed shape, noted whether it needs `--full-refresh`
