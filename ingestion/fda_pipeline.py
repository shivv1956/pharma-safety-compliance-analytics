"""openFDA ingestion: drug adverse events (FAERS) and drug recalls (enforcement).

Both resources land raw, nested JSON into Snowflake (Bronze) with append-only
semantics and dlt-managed incremental cursors.
"""

import sys
from datetime import date, timedelta
from typing import Any, Iterator, Optional

import dlt
from dlt.sources.helpers.requests import HTTPError
from dlt.sources.helpers.rest_client import RESTClient
from dlt.sources.helpers.rest_client.auth import APIKeyAuth
from dlt.sources.helpers.rest_client.paginators import OffsetPaginator
from dlt.sources.rest_api import RESTAPIConfig, rest_api_resources

# live bar in a terminal, periodic log lines in CI (GitHub Actions)
PROGRESS = "tqdm" if sys.stderr.isatty() else "log"

BASE_URL = "https://api.fda.gov/"
PAGE_SIZE = 1000  # openFDA hard maximum for `limit`
DATE_FMT = "%Y%m%d"


def _auth(api_key: Optional[str]) -> Optional[APIKeyAuth]:
    return APIKeyAuth(name="api_key", api_key=api_key, location="query") if api_key else None


@dlt.source(name="openfda")
def openfda_source(
    api_key: Optional[str] = dlt.secrets.value,
    events_initial_date: Optional[str] = None,
    events_end_date: Optional[str] = None,
    recalls_initial_date: str = "20240101",
) -> Any:
    """
    Args:
        api_key: openFDA API key (optional, but raises the rate limit).
        events_initial_date: first `receivedate` (YYYYMMDD) to pull on the very
            first run. Defaults to 20260601 (~30 days before the newest FAERS data,
            which lags real time by months). Later runs resume from dlt state.
        events_end_date: last `receivedate` (YYYYMMDD), inclusive. Setting it makes
            a bounded backfill: dlt ignores saved cursor state and does not update it.
        recalls_initial_date: first `report_date` (YYYYMMDD) for recalls.
    """
    if events_initial_date is None:
        events_initial_date = "20260601"

    # FAERS is large and openFDA refuses to page past skip=25000, so a single
    # open-ended query cannot work. We slice into one-day windows instead.
    @dlt.resource(name="adverse_events", write_disposition="append", primary_key="safetyreportid")
    def adverse_events(
        receivedate: dlt.sources.incremental[str] = dlt.sources.incremental(
            "receivedate", initial_value=events_initial_date, end_value=events_end_date
        ),
    ) -> Iterator[Any]:
        client = RESTClient(base_url=BASE_URL, auth=_auth(api_key))
        day = date.fromisoformat(
            f"{receivedate.start_value[:4]}-{receivedate.start_value[4:6]}-{receivedate.start_value[6:8]}"
        )
        last_day = date.today()
        if events_end_date:
            last_day = min(last_day, date.fromisoformat(
                f"{events_end_date[:4]}-{events_end_date[4:6]}-{events_end_date[6:8]}"
            ))
        while day <= last_day:
            stamp = day.strftime(DATE_FMT)
            try:
                yield from client.paginate(
                    "drug/event.json",
                    params={
                        "search": f"receivedate:[{stamp} TO {stamp}]",
                        "sort": "receivedate:asc",
                        "limit": PAGE_SIZE,
                    },
                    paginator=OffsetPaginator(
                        limit=PAGE_SIZE,
                        offset_param="skip",
                        limit_param="limit",
                        total_path="meta.results.total",
                    ),
                    data_selector="results",
                )
            except HTTPError as e:
                # openFDA answers 404 (not an empty list) when a window has no matches
                if e.response is None or e.response.status_code != 404:
                    raise
            day += timedelta(days=1)

    # Recalls are low volume (hundreds per year), so the declarative config is enough.
    recalls_config: RESTAPIConfig = {
        "client": {"base_url": BASE_URL, "auth": _auth(api_key)},
        "resources": [
            {
                "name": "recalls",
                "primary_key": "recall_number",
                "write_disposition": "append",
                "endpoint": {
                    "path": "drug/enforcement.json",
                    "data_selector": "results",
                    "paginator": {
                        "type": "offset",
                        "limit": PAGE_SIZE,
                        "offset_param": "skip",
                        "limit_param": "limit",
                        "total_path": "meta.results.total",
                    },
                    "params": {
                        "search": "report_date:[{incremental.start_value} TO 20991231]",
                        "sort": "report_date:asc",
                    },
                    "incremental": {
                        "cursor_path": "report_date",
                        "initial_value": recalls_initial_date,
                    },
                    "response_actions": [{"status_code": 404, "action": "ignore"}],
                },
            }
        ],
    }

    yield adverse_events
    yield from rest_api_resources(recalls_config)


def load_fda(
    events_initial_date: Optional[str] = None,
    events_end_date: Optional[str] = None,
    recalls_initial_date: str = "20240101",
    events_only: bool = False,
) -> None:
    pipeline = dlt.pipeline(
        pipeline_name="openfda",
        destination="snowflake",
        dataset_name="openfda",
        progress=PROGRESS,
    )
    source = openfda_source(
        events_initial_date=events_initial_date,
        events_end_date=events_end_date,
        recalls_initial_date=recalls_initial_date,
    )
    if events_only:
        source = source.with_resources("adverse_events")
    load_info = pipeline.run(source)
    print(load_info)  # noqa: T201


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="No flags = the daily incremental run (resumes from dlt state)."
    )
    parser.add_argument("--day", help="backfill adverse events for one receivedate (YYYYMMDD)")
    parser.add_argument("--from", dest="start", help="backfill adverse events from this receivedate (YYYYMMDD)")
    parser.add_argument("--to", dest="end", help="backfill adverse events up to this receivedate, inclusive")
    parser.add_argument("--recalls-from", default="20240101", help="first recall report_date (YYYYMMDD)")
    args = parser.parse_args()

    start, end = args.day or args.start, args.day or args.end
    # a bounded backfill only touches adverse events; recalls come from the daily run
    load_fda(start, end, args.recalls_from, events_only=bool(start or end))
