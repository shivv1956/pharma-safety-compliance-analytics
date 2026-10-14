"""Compliance watch agent: perceive -> decide -> act.

perceive  read the manufacturers flagged by mart_compliance_risk_signals, and pull the
          context behind each flag (top drugs, Class I recalls)
decide    skip manufacturers that already have an alert for the same year and level
act       draft a plain-language brief and log it to the compliance_alerts table

The brief is written from a template today. `draft_brief` is the one place to swap in an
LLM (Snowflake Cortex, or the Claude API) later; the rest of the loop does not change.

Usage (from the repo root):
    uv run python agent/compliance_watch.py --dry-run   # print briefs, write nothing
    uv run python agent/compliance_watch.py             # log new alerts

Connection: the `pharma_safety` dbt profile (~/.dbt/profiles.yml, target `dev`) unless
SNOWFLAKE_ACCOUNT / SNOWFLAKE_USER / SNOWFLAKE_PASSWORD / SNOWFLAKE_WAREHOUSE /
SNOWFLAKE_ROLE are set (for CI).
"""

import argparse
import json
import os
from pathlib import Path
from typing import Any

import snowflake.connector
import yaml
from snowflake.connector import DictCursor, SnowflakeConnection

ALERTS_DDL = """
create table if not exists {alerts} (
    alert_id        varchar default uuid_string(),
    created_at      timestamp_ntz default current_timestamp(),
    manufacturer_key varchar not null,
    manufacturer_name varchar not null,
    analysis_year   number not null,
    alert_level     varchar not null,
    signals         variant,
    brief           varchar,
    brief_method    varchar,
    status          varchar default 'open',
    reviewer_notes  varchar
)
"""


def connect(database: str | None) -> SnowflakeConnection:
    if os.getenv("SNOWFLAKE_ACCOUNT"):
        params = {
            "account": os.environ["SNOWFLAKE_ACCOUNT"],
            "user": os.environ["SNOWFLAKE_USER"],
            "password": os.environ["SNOWFLAKE_PASSWORD"],
            "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
            "role": os.environ["SNOWFLAKE_ROLE"],
            "database": database or os.environ["SNOWFLAKE_DATABASE"],
        }
    else:
        profiles = yaml.safe_load((Path.home() / ".dbt" / "profiles.yml").read_text())
        profile = profiles["pharma_safety"]
        target = profile["outputs"][profile["target"]]
        params = {
            key: target[key] for key in ("account", "user", "password", "warehouse", "role")
        }
        params["database"] = database or target["database"]
    return snowflake.connector.connect(**params)


def query(conn: SnowflakeConnection, sql: str, *args: Any) -> list[dict[str, Any]]:
    cur = conn.cursor(DictCursor)
    try:
        cur.execute(sql, args or None)
        return [{k.lower(): v for k, v in row.items()} for row in cur.fetchall()]
    finally:
        cur.close()


def perceive(conn: SnowflakeConnection, marts_schema: str) -> list[dict[str, Any]]:
    """Flagged manufacturers, critical first."""
    return query(
        conn,
        f"""
        select * from {marts_schema}.mart_compliance_risk_signals
        where is_flagged
        order by iff(alert_level = 'critical', 0, 1), total_payments_usd desc
        """,
    )


def context_for(conn: SnowflakeConnection, marts_schema: str, signal: dict[str, Any]) -> dict[str, Any]:
    """The drugs and recalls behind a flag."""
    key, year = signal["manufacturer_key"], signal["program_year"]
    drugs = query(
        conn,
        f"""
        select d.generic_name, count(distinct f.adverse_event_report_id) as serious_reports
        from {marts_schema}.fct_adverse_events f
        join {marts_schema}.dim_drugs d using (drug_key)
        where f.manufacturer_key = %s and f.is_suspect and f.is_serious and year(f.received_date) = %s
        group by 1 order by 2 desc limit 3
        """,
        key,
        year,
    )
    recalls = query(
        conn,
        f"""
        select report_date, recall_status, left(recall_reason, 160) as recall_reason
        from {marts_schema}.fct_recalls
        where manufacturer_key = %s and is_class_i and year(report_date) = %s
        order by report_date desc limit 2
        """,
        key,
        year,
    )
    return {"top_drugs": drugs, "class_i_recalls": recalls}


def decide(signal: dict[str, Any], already_alerted: set[tuple[str, int, str]]) -> bool:
    return (signal["manufacturer_key"], signal["program_year"], signal["alert_level"]) not in already_alerted


def draft_brief(signal: dict[str, Any], context: dict[str, Any]) -> str:
    h1, h2 = signal["serious_reports_h1"], signal["serious_reports_h2"]
    change = f"{(h2 - h1) / h1:+.0%}" if h1 else "n/a"
    lines = [
        f"{signal['alert_level'].upper()}: {signal['manufacturer_name']} ({signal['program_year']})",
        "",
        f"- Payments to physicians: ${signal['total_payments_usd']:,.0f} across {signal['physicians_paid']:,} physicians; "
        f"{signal['top_decile_share']:.0%} went to the top 10% of them, "
        f"{signal['top10_share']:.0%} to the 10 most-paid.",
        f"- Serious adverse-event reports naming its drugs as suspect: {h1:,} in H1 vs {h2:,} in H2 ({change}).",
    ]
    if context["top_drugs"]:
        drugs = ", ".join(f"{d['generic_name'].title()} ({d['serious_reports']:,})" for d in context["top_drugs"])
        lines.append(f"- Drugs with the most serious reports: {drugs}.")
    if signal["class_i_recalls"]:
        lines.append(f"- Class I recalls reported in {signal['program_year']}: {signal['class_i_recalls']}.")
        for r in context["class_i_recalls"]:
            lines.append(f"    - {r['report_date']} ({r['recall_status']}): {r['recall_reason']}")
    else:
        lines.append("- No Class I recall was reported this year; the alert is raised on the other three signals.")
    lines += [
        "",
        "Why it matters: concentrated payments to a few physicians alongside rising serious safety "
        "reports is a pattern compliance teams review for conflict of interest.",
        "Caveats: this is a pattern to review, not evidence of wrongdoing. Adverse-event reports are "
        "unverified, FAERS lags real time, and about 17% of drug rows cannot be tied to a manufacturer.",
    ]
    return "\n".join(lines)


def act(conn: SnowflakeConnection, alerts: str, signal: dict[str, Any], brief: str) -> None:
    signals = {
        k: signal[k]
        for k in (
            "total_payments_usd", "physicians_paid", "top_decile_share", "top10_share", "hhi",
            "suspect_reports", "serious_reports", "serious_reports_h1", "serious_reports_h2",
            "recalls", "class_i_recalls", "signals_met",
        )
    }
    cur = conn.cursor()
    try:
        cur.execute(
            f"""insert into {alerts}
                (manufacturer_key, manufacturer_name, analysis_year, alert_level, signals, brief, brief_method)
                select %s, %s, %s, %s, parse_json(%s), %s, 'template'""",
            (
                signal["manufacturer_key"], signal["manufacturer_name"], signal["program_year"],
                signal["alert_level"], json.dumps(signals, default=float), brief,
            ),
        )
    finally:
        cur.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--database", help="database holding the marts (default: the profile's)")
    parser.add_argument("--marts-schema", default="marts")
    parser.add_argument("--alerts-schema", default="agent", help="schema for the compliance_alerts table")
    parser.add_argument("--dry-run", action="store_true", help="print briefs without writing")
    args = parser.parse_args()

    conn = connect(args.database)
    try:
        database = query(conn, "select current_database() as db")[0]["db"]
        marts = f"{database}.{args.marts_schema}"
        alerts = f"{database}.{args.alerts_schema}.compliance_alerts"
        if not args.dry_run:
            query(conn, f"create schema if not exists {database}.{args.alerts_schema}")
            query(conn, ALERTS_DDL.format(alerts=alerts))
            existing = query(conn, f"select manufacturer_key, analysis_year, alert_level from {alerts}")
        else:
            try:
                existing = query(conn, f"select manufacturer_key, analysis_year, alert_level from {alerts}")
            except snowflake.connector.errors.ProgrammingError:
                existing = []
        already = {(r["manufacturer_key"], r["analysis_year"], r["alert_level"]) for r in existing}

        flagged = perceive(conn, marts)
        print(f"perceive: {len(flagged)} flagged manufacturers; {len(already)} alerts already logged")
        logged = 0
        for signal in flagged:
            if not decide(signal, already):
                continue
            brief = draft_brief(signal, context_for(conn, marts, signal))
            if args.dry_run:
                print("\n" + "=" * 72 + "\n" + brief)
            else:
                act(conn, alerts, signal, brief)
            logged += 1
        print(f"\nact: {logged} new alerts {'drafted (dry run)' if args.dry_run else 'logged to ' + alerts}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
