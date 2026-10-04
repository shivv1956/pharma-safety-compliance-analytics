"""CMS Open Payments bulk load from the published yearly CSV.

The REST datastore API is too slow to page through a full program year
(~15M rows, ~5M after our filter), so full-year loads stream the CSV that CMS
publishes for each year instead. It lands in the same table as the API
pipeline (`general_payments`), with the same filter, columns and merge key.
"""

import csv
import sys
from typing import Any, Iterator, Optional

import dlt
import requests

sys.stdout.reconfigure(line_buffering=True)

PROGRESS = "tqdm" if sys.stderr.isatty() else "log"

METASTORE_URL = "https://openpaymentsdata.cms.gov/api/1/metastore/schemas/dataset/items"
# the CMS Akamai gateway returns 403 for unfamiliar User-Agents
HEADERS = {"User-Agent": "python-requests/2.32.3"}
CHUNK_ROWS = 200_000  # rows per extract/normalize/load cycle, bounds memory and runner disk

TYPE_COLUMN = "covered_recipient_type"
PRODUCT_COLUMN = "indicate_drug_or_biological_or_device_or_medical_supply_1"


def csv_download_url(program_year: int) -> str:
    """Current download URL of the year's CSV (the file name contains the publish date)."""
    items = requests.get(
        METASTORE_URL, params={"show-reference-ids": ""}, headers=HEADERS, timeout=60
    ).json()
    title = f"{program_year} General Payment Data"
    for item in items:
        if item["title"] == title:
            return item["distribution"][0]["data"]["downloadURL"]
    raise ValueError(f"no '{title}' dataset in the CMS metastore")


def physician_drug_rows(url: str, skip_rows: int = 0) -> Iterator[dict]:
    """Stream the CSV and yield physician/drug payment rows with API-style (lowercase) columns.

    `skip_rows` skips that many *matching* rows, to resume an interrupted load.
    """
    matched = 0
    with requests.get(url, headers=HEADERS, stream=True, timeout=(30, 300)) as resp:
        resp.raise_for_status()
        lines = (line.decode("utf-8-sig", errors="replace") for line in resp.iter_lines())
        reader = csv.DictReader(lines)
        reader.fieldnames = [name.lower() for name in reader.fieldnames or []]
        for row in reader:
            if row[TYPE_COLUMN] != "Covered Recipient Physician" or row[PRODUCT_COLUMN] != "Drug":
                continue
            matched += 1
            if matched > skip_rows:
                yield row


@dlt.resource(
    name="general_payments",
    primary_key=["program_year", "record_id"],
    write_disposition="merge",
)
def general_payments(rows: list[dict]) -> Iterator[dict]:
    yield from rows


def load_payments_bulk(
    program_year: int = 2024,
    max_rows: Optional[int] = None,
    skip_rows: int = 0,
    destination: Any = "snowflake",
    pipelines_dir: Optional[str] = None,
) -> None:
    url = csv_download_url(program_year)
    print(f"Streaming {url}")  # noqa: T201

    pipeline = dlt.pipeline(
        pipeline_name="cms_open_payments",
        destination=destination,
        dataset_name="cms_open_payments",
        progress=PROGRESS,
        pipelines_dir=pipelines_dir,
    )

    total = 0
    chunk: list[dict] = []

    def flush() -> None:
        nonlocal chunk
        if not chunk:
            return
        pipeline.run(general_payments(chunk))
        print(f"loaded {skip_rows + total:,} rows (program year {program_year})")  # noqa: T201
        chunk = []

    for row in physician_drug_rows(url, skip_rows):
        row["program_year"] = program_year
        chunk.append(row)
        total += 1
        if len(chunk) >= CHUNK_ROWS:
            flush()
        if max_rows and total >= max_rows:
            break
    flush()
    print(f"done: {total:,} rows loaded this run")  # noqa: T201


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Bulk-load one Open Payments program year from CSV.")
    parser.add_argument("--year", type=int, default=2024, help="Open Payments program year")
    parser.add_argument("--max-rows", type=int, default=0, help="stop after this many rows (0 = whole file)")
    parser.add_argument(
        "--skip-rows", type=int, default=0, help="skip this many matching rows (resume a load; see 'loaded N rows' log lines)"
    )
    args = parser.parse_args()
    load_payments_bulk(args.year, args.max_rows or None, args.skip_rows)
