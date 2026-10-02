# Capstone Project: Pharma Compliance and Drug Safety Intelligence Warehouse

A 4-week, enterprise-style dbt project built on three genuinely live, free US government APIs, with an agentic AI compliance layer and a Power BI dashboard on top.

## 1. Project concept

You will build a warehouse that answers a real pharma-industry question: is there a relationship between how much a drug manufacturer pays physicians and the safety signals (adverse events, recalls) tied to that manufacturer's drugs? This is a genuine conflict-of-interest / commercial-compliance analysis pattern used in real pharmacovigilance and compliance teams.

Three live sources feed the warehouse:

- **openFDA Adverse Events (FAERS)**: real reports of drug side effects, submitted continuously to the FDA
- **openFDA Drug Enforcement (Recalls)**: real drug recall records, classified by severity
- **CMS Open Payments (Sunshine Act)**: real payments from drug/device manufacturers to physicians, published by the US government

None of this is synthetic. It is messy in the way real regulatory data is messy: inconsistent drug naming across sources, deeply nested JSON, missing fields, and firm/manufacturer names that never quite match between datasets.

**Pipeline shape:**

```text
Live APIs (openFDA x2, CMS Open Payments)
  -> scheduled dlt pipelines
  -> Bronze (raw JSON, append-only)
  -> Silver/staging (flattened, cleaned, conformed)
  -> Intermediate (drug/manufacturer identity resolution + Cortex AI enrichment)
  -> Gold marts (a multi-fact "galaxy" schema)
  -> Power BI dashboard
```

A compliance agent watches Gold and raises flagged cases.

## 2. The three live data sources

### openFDA Adverse Events

Endpoint: <https://api.fda.gov/drug/event.json>

- One record per safety report; each report can list multiple drugs and multiple reactions (nested JSON arrays), a genuine semi-structured data challenge.
- Free without a key at a modest rate; register for a free API key for higher throughput.
- Ingest with dlt's `rest_api_source`: configure an `incremental` block on `receivedate` so dlt automatically tracks the last value pulled and only requests new records, with dlt's built-in offset paginator handling `skip`/`limit` paging for you.

### openFDA Drug Enforcement (Recalls)

Endpoint: <https://api.fda.gov/drug/enforcement.json>

- Real recall records: firm name, product description, recall reason (free text), classification (Class I/II/III = most to least severe), status, distribution pattern.
- Same dlt `rest_api_source` pattern, with `incremental` configured on `report_date`. dlt persists its own state between runs, so no custom checkpoint file is needed.

### CMS Open Payments (Sunshine Act)

Endpoint: <https://openpaymentsdata.cms.gov/api>

- Real payments (research, consulting, speaking, meals, travel) from manufacturers to physicians and teaching hospitals, with physician NPI, specialty, manufacturer name, drug/device name, and amount.
- Published once per program year rather than continuously, but you still pull it live via the API, as a second dlt `rest_api_source` on a slower schedule (e.g. monthly) rather than downloading a static file. The freshness cadence itself becomes something you configure and test for.

### The identity-resolution problem

Drug names and manufacturer/firm names are spelled and formatted differently across all three sources (e.g. "Pfizer Inc.", "PFIZER LABORATORIES DIV OF PFIZER INC", "Pfizer"). Conforming these into shared `dim_drugs` and `dim_manufacturers` is the core "enterprise" challenge of this project, the real-world equivalent of master data management.

## 3. Environment setup (Week 1, Days 1-2)

1. Create a Snowflake trial account in a Cortex-supported region (e.g. AWS US West 2 or Azure East US). Week 3's AI layer depends on Snowflake Cortex.
2. Create a dedicated `DBT_ROLE` and `DBT_WH` warehouse (X-Small, auto-suspend 60s) instead of using `ACCOUNTADMIN`.
3. Install dbt Core + the Snowflake adapter locally for the Cloud CLI, and connect the same repo to dbt Cloud. This project uses a hybrid setup that matches how most enterprises actually run dbt: git-based development (local editor or dbt Cloud IDE), with dbt Cloud as the orchestration/CI layer.
4. In dbt Cloud, create three Environments, each pointing at its own Snowflake database:

   | Environment | Deploy type | Purpose | Database |
   | --- | --- | --- | --- |
   | Development | Development | Your personal dev credentials | `PHARMA_DEV` |
   | Staging/CI | Deployment | Used only by the CI job | `PHARMA_TEST` |
   | Production | Deployment | Used by the scheduled prod job | `PHARMA_PROD` |

5. Connect dbt Cloud to your GitHub repo via its native integration (not a manual webhook) so PRs can trigger dbt Cloud Jobs automatically.
6. Install dlt with the Snowflake extra (`pip install "dlt[snowflake]"`) for ingestion. A native Snowflake destination means you never hand-write `COPY INTO`/staging logic. Ingestion stays outside dbt Cloud (dbt Cloud orchestrates dbt runs, not arbitrary Python), so `fda_pipeline.py`/`payments_pipeline.py` continue to run on GitHub Actions cron, independent of the dbt Cloud jobs below.
7. Register a free openFDA API key (raises your rate limit) and store it, plus any CMS API credentials, as GitHub Actions secrets (for ingestion) and as dbt Cloud environment variables (for anything the Cortex/agent models need at run time).
8. Initialize git, push to GitHub, and set up a `main` + feature-branch workflow with a PR template.

## 4. Project structure

```text
pharma_safety/
  ingestion/
    fda_pipeline.py                  -- dlt rest_api_source: adverse_events + recalls resources, built-in incremental cursors
    payments_pipeline.py             -- dlt rest_api_source: CMS Open Payments resource, monthly cadence
    .dlt/
      secrets.toml                   -- Snowflake + API credentials (gitignored, or GitHub Actions secrets in CI)
      config.toml                    -- pipeline-level config
  models/
    staging/
      stg_adverse_events.sql         -- flattens nested drug/reaction arrays (FLATTEN + VARIANT)
      stg_recalls.sql
      stg_open_payments.sql
      _staging__sources.yml          -- per-source freshness configs (different cadence per source)
      _staging__models.yml
    intermediate/
      int_drug_resolution.sql        -- conforms drug names/NDC codes across all 3 sources
      int_manufacturer_resolution.sql -- conforms firm/manufacturer names
      int_events_ai_enriched.sql     -- Cortex: severity classification + summary of reaction narratives
      int_recalls_ai_enriched.sql    -- Cortex: risk classification of recall_reason text
    marts/
      fct_adverse_events.sql         -- incremental
      fct_recalls.sql                -- incremental
      fct_payments.sql               -- incremental
      dim_drugs.sql
      dim_manufacturers.sql
      dim_physicians.sql
      dim_date.sql
      _marts__models.yml
  snapshots/
    dim_drugs_snapshot.sql           -- SCD2 on drug marketing status changes
  macros/
    generate_schema_name.sql
    normalize_firm_name.sql
  tests/
    assert_recall_classification_valid.sql
  agent/
    compliance_watch.py              -- joins the three facts by manufacturer, flags risk, drafts a brief via Cortex
  dbt_project.yml
  packages.yml                       -- dbt_utils, dbt_expectations, dbt_project_evaluator
```

## 5. Week-by-week roadmap

### Week 1: Live ingestion and the semi-structured data problem

- **Days 1-2:** Environment setup (above). Scaffold `fda_pipeline.py` with `dlt init rest_api snowflake`, then define two dlt resources (`adverse_events`, `recalls`) on a shared `rest_api_source`, each with its own incremental cursor (`receivedate` / `report_date`) and `write_disposition: "append"`. Run `pipeline.run(source)` to land raw JSON into Bronze with dlt's own `_dlt_load_id`/`_dlt_loaded_at` metadata columns. Pagination, schema inference, and incremental state are all handled by dlt. Schedule the script via GitHub Actions cron (e.g. every few hours).
- **Day 3:** Write `sources.yml` with per-source freshness blocks (pointed at dlt's `_dlt_loaded_at` column); build `stg_recalls` (simpler, flat) first to get the pattern down.
- **Day 4:** Build `stg_adverse_events`. Use `LATERAL FLATTEN` on the nested `patient.drug[]` and `patient.reaction[]` arrays so one report becomes multiple clean rows. This is the most technically interesting problem of the whole project.
- **Day 5:** Generic tests (`not_null`, `accepted_values` on recall classification) and run `dbt source freshness` to confirm both feeds are landing on schedule.

### Week 2: Identity resolution, CMS Open Payments, and the multi-fact schema

- **Days 1-2:** Write `payments_pipeline.py` as a second dlt `rest_api_source` (different API shape, slower cadence, scheduled monthly rather than hourly) and `stg_open_payments`.
- **Day 3:** Build `int_drug_resolution` and `int_manufacturer_resolution`. Normalize casing/punctuation/legal suffixes (INC, LLC, CORP, DIV OF) and fuzzy-match names across all three sources into conformed dimension keys.
- **Day 4:** Build the marts as a proper fact constellation: `fct_adverse_events`, `fct_recalls`, and `fct_payments` all sharing `dim_drugs`, `dim_manufacturers`, and `dim_date`. This is a real multi-fact star/galaxy schema, not just one fact table.
- **Day 5:** Add `dim_drugs_snapshot` for SCD2 on marketing status; write schema + singular tests; generate dbt docs.

### Week 3: Agentic AI compliance layer (the core learning goal)

- **Day 1:** Enable Snowflake Cortex; test `SNOWFLAKE.CORTEX.COMPLETE()` and `CLASSIFY_TEXT()` on real recall-reason and adverse-event narrative text in a worksheet.
- **Days 2-3:** Build `int_recalls_ai_enriched` (risk-category classification from `recall_reason`) and `int_events_ai_enriched` (severity classification + one-line summary), both as incremental models.
- **Day 4:** Build `agent/compliance_watch.py`, a perceive-decide-act script that:
  - joins Gold-layer facts by manufacturer over a rolling window;
  - flags manufacturers with high physician-payment concentration, rising serious adverse events, and a recent Class I recall;
  - calls Cortex to draft a plain-language compliance brief;
  - logs it to a `compliance_alerts` table.
- **Day 5:** Run the agent, review its flagged cases, and document any false positives. This is a normal and useful part of building agentic systems.

### Week 4: CI/CD, governance, and the dashboard

- **Days 1-2:** Build this in dbt Cloud Jobs instead of hand-rolled GitHub Actions dbt steps (the realistic enterprise pattern, and also directly exam-tested):
  - A **CI job** on the Staging/CI environment, triggered automatically "on pull request" via the native GitHub integration, running `dbt build --select state:modified+` with deferral turned on against the Production job's last run. The CI job only builds what changed and resolves unbuilt upstream `ref()`s from Production state instead of rebuilding the whole DAG.
  - A **Production job** on the Production environment, triggered by a cron schedule (e.g. daily after the CMS/openFDA ingestion crons finish), running `dbt build`, generating docs, and producing the `manifest.json`/`run_results.json` artifacts that the next CI run defers against.
  - Keep ingestion (`fda_pipeline.py`/`payments_pipeline.py`) on GitHub Actions cron, fully separate from dbt Cloud. This hybrid "EL on GitHub Actions, T orchestrated in dbt Cloud" split is itself a common real enterprise architecture.
  - Practice `dbt clone` once from a feature-branch job into a prod-like schema, and `dbt retry` after deliberately breaking then fixing a model. Both are explicitly tested exam skills that are easy to skip if you only ever use GitHub Actions.
- **Day 3:** Install and run `dbt_project_evaluator`, and fix flagged violations (undocumented models, direct joins to source, etc.). Browse the DAG and model health in dbt Explorer instead of a locally served dbt docs, and define an exposure for the Power BI dashboard so it shows up in Explorer's lineage.
- **Day 4:** Build the Power BI dashboard against `PHARMA_PROD`:
  - Adverse event trends and severity mix by drug and manufacturer
  - Recall risk heatmap by classification and manufacturer
  - Physician payment concentration vs. adverse-event/recall rate by manufacturer (the core conflict-of-interest view)
  - A "Compliance Alerts" page showing the agent's flagged manufacturers and AI-drafted briefs
- **Day 5:** Write a README documenting the architecture, the identity-resolution approach, and what you'd change at real enterprise scale (data governance sign-off on drug/manufacturer master data, dbt Mesh across a safety team and a commercial-compliance team, semantic layer for a shared "safety signal" metric).

## 6. What this project deliberately forces you to learn

- Ingesting from genuinely live, real government APIs on different freshness cadences, not a static file
- Using a modern EL framework (dlt) instead of hand-rolled polling scripts. Pagination, incremental state, and schema evolution are handled for you, closer to how real data platforms are built today
- Flattening deeply nested JSON from a live API into clean relational models (a real semi-structured data skill)
- Master-data-style identity resolution across three independent real-world sources
- A true multi-fact "galaxy schema" instead of a single star schema
- SCD2 history via snapshots
- In-warehouse AI (Snowflake Cortex) for text classification and summarization on real regulatory text
- A genuine agentic loop that cross-references multiple facts, reasons about risk, and produces a human-readable output
- CI/CD for both dbt transformations and independently scheduled ingestion
- dbt Cloud-specific mechanics the certification exam tests directly: Environments, Jobs, deferral, `dbt clone`/`dbt retry`, and dbt Explorer, now exercised for real instead of approximated through GitHub Actions alone
- Translating a genuinely cross-domain (safety + commercial) warehouse into a business-relevant BI dashboard

## 7. Stretch goals if you finish early

- Add ClinicalTrials.gov data to connect a drug's trial history to its later safety signals.
- Convert the identity-resolution logic into a reusable dbt package so it could be applied to a new data source without rewriting SQL.
- Add dbt unit tests on the drug/manufacturer name-normalization macros, separate from data tests.
