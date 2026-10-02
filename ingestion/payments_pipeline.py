"""CMS Open Payments (Sunshine Act) ingestion: general payments to physicians.

Published once per program year, so this runs on a slower (monthly) schedule.
The full year is ~15M rows, so we filter server-side to physician payments
tied to a drug/biological and cap the rows per run (see `max_rows`).
"""

import sys
from typing import Any, Optional

import dlt
from dlt.sources.rest_api import RESTAPIConfig, rest_api_resources

# live bar in a terminal, periodic log lines in CI (GitHub Actions)
PROGRESS = "tqdm" if sys.stderr.isatty() else "log"

BASE_URL = "https://openpaymentsdata.cms.gov/api/1/"
PAGE_SIZE = 500  # the datastore rejects larger limits

# "<year> General Payment Data" dataset ids from the CMS metastore
GENERAL_PAYMENT_DATASETS = {
    2022: "df01c2f8-dc1f-4e79-96cb-8208beaf143c",
    2023: "fb3a65aa-c901-4a38-a813-b04b00dfa2a9",
    2024: "e6b17c6a-2534-4207-a4a1-6746a14911ff",
    2025: "fb0b1734-1410-429d-92f6-3f4b35218e5e",
}


@dlt.source(name="cms_open_payments")
def open_payments_source(
    program_year: int = 2024,
    max_rows: Optional[int] = 100_000,
) -> Any:
    """
    Args:
        program_year: Open Payments program year to pull.
        max_rows: cap on rows per run (None or 0 = the whole filtered year,
            several million rows).
    """
    if program_year not in GENERAL_PAYMENT_DATASETS:
        raise ValueError(f"program_year must be one of {sorted(GENERAL_PAYMENT_DATASETS)}")
    dataset_id = GENERAL_PAYMENT_DATASETS[program_year]

    def tag_program_year(row: dict) -> dict:
        row["program_year"] = program_year
        return row

    config: RESTAPIConfig = {
        # the CMS Akamai gateway returns 403 for unfamiliar User-Agents (dlt/x.y, custom, browser)
        "client": {"base_url": BASE_URL, "headers": {"User-Agent": "python-requests/2.32.3"}},
        "resources": [
            {
                "name": "general_payments",
                # record_id is only guaranteed unique within one program year
                "primary_key": ["program_year", "record_id"],
                # the year is republished/corrected as a whole, so upsert on the key
                "write_disposition": "merge",
                "processing_steps": [{"map": tag_program_year}],
                "endpoint": {
                    "path": f"datastore/query/{dataset_id}/0",
                    "data_selector": "results",
                    "paginator": {
                        "type": "offset",
                        "limit": PAGE_SIZE,
                        "offset_param": "offset",
                        "limit_param": "limit",
                        "total_path": "count",
                    },
                    "params": {
                        "conditions[0][property]": "covered_recipient_type",
                        "conditions[0][value]": "Covered Recipient Physician",
                        "conditions[1][property]": "indicate_drug_or_biological_or_device_or_medical_supply_1",
                        "conditions[1][value]": "Drug",
                    },
                },
            }
        ],
    }

    resources = rest_api_resources(config)
    if max_rows:
        resources = [r.add_limit(-(-max_rows // PAGE_SIZE)) for r in resources]
    yield from resources


def load_payments(program_year: int = 2024, max_rows: Optional[int] = 100_000) -> None:
    pipeline = dlt.pipeline(
        pipeline_name="cms_open_payments",
        destination="snowflake",
        dataset_name="cms_open_payments",
        progress=PROGRESS,
    )
    load_info = pipeline.run(open_payments_source(program_year=program_year, max_rows=max_rows))
    print(load_info)  # noqa: T201


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--year", type=int, default=2024, help="Open Payments program year")
    parser.add_argument("--max-rows", type=int, default=100_000, help="row cap for this run (0 = no cap)")
    args = parser.parse_args()
    load_payments(args.year, args.max_rows)
