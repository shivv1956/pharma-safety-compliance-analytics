"""Pharma compliance & drug safety dashboard (Streamlit) over the dbt marts.

Run from the repo root:
    uv run streamlit run dashboard/app.py

Connection: SNOWFLAKE_* env vars when set, else the `pharma_safety` dbt profile.
Set SNOWFLAKE_DATABASE (or DASHBOARD_DATABASE) to point at another database, e.g. PHARMA_PROD.
"""

import os
from pathlib import Path

import pandas as pd
import plotly.express as px
import snowflake.connector
import streamlit as st
import yaml

st.set_page_config(page_title="Pharma Safety & Compliance", page_icon="💊", layout="wide")


@st.cache_resource
def connection():
    if os.getenv("SNOWFLAKE_ACCOUNT"):
        params = {
            "account": os.environ["SNOWFLAKE_ACCOUNT"],
            "user": os.environ["SNOWFLAKE_USER"],
            "password": os.environ["SNOWFLAKE_PASSWORD"],
            "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
            "role": os.environ["SNOWFLAKE_ROLE"],
            "database": os.getenv("DASHBOARD_DATABASE") or os.environ["SNOWFLAKE_DATABASE"],
        }
    else:
        profiles = yaml.safe_load((Path.home() / ".dbt" / "profiles.yml").read_text())
        profile = profiles["pharma_safety"]
        target = profile["outputs"][profile["target"]]
        params = {k: target[k] for k in ("account", "user", "password", "warehouse", "role", "database")}
        params["database"] = os.getenv("DASHBOARD_DATABASE") or params["database"]
    return snowflake.connector.connect(**params)


@st.cache_data(ttl=3600, show_spinner="Querying Snowflake...")
def run(sql: str) -> pd.DataFrame:
    cur = connection().cursor()
    try:
        cur.execute(sql)
        df = cur.fetch_pandas_all()
    finally:
        cur.close()
    df.columns = [c.lower() for c in df.columns]
    return df


MARTS = "marts"
SEVERITY_COLS = {
    "is_death": "Death",
    "is_life_threatening": "Life-threatening",
    "is_disabling": "Disabling",
    "is_hospitalization": "Hospitalization",
}

st.title("Pharma Compliance & Drug Safety")
st.caption(
    "openFDA adverse events and recalls joined to CMS Open Payments through a conformed "
    "drug and manufacturer model. Adverse-event reports are unverified and FAERS lags real time."
)

tab_events, tab_recalls, tab_conflict, tab_alerts = st.tabs(
    ["Adverse events", "Recalls", "Payments vs safety", "Compliance alerts"]
)

# --- Adverse events ----------------------------------------------------------------------
with tab_events:
    monthly = run(
        f"""select date_trunc('month', month_start) as month, sum(suspect_reports) as reports,
                   sum(serious_reports) as serious, sum(death_reports) as deaths
            from {MARTS}.mart_manufacturer_monthly
            where month_start >= '2020-01-01' group by 1 order by 1"""
    )
    c1, c2 = st.columns([3, 2])
    with c1:
        st.subheader("Monthly reports naming a suspect drug")
        fig = px.line(monthly, x="month", y=["reports", "serious", "deaths"],
                      labels={"value": "reports", "month": "", "variable": ""})
        st.plotly_chart(fig, width="stretch")

    years = run(f"select distinct year(received_date) y from {MARTS}.fct_adverse_events where received_date >= '2020-01-01' order by 1 desc")["y"].tolist()
    year = c2.selectbox("Year", years)
    sev = run(
        f"""select d.generic_name,
                   count(distinct iff(f.is_death, f.adverse_event_report_id, null)) as is_death,
                   count(distinct iff(f.is_life_threatening and not f.is_death, f.adverse_event_report_id, null)) as is_life_threatening,
                   count(distinct iff(f.is_disabling and not f.is_death and not f.is_life_threatening, f.adverse_event_report_id, null)) as is_disabling,
                   count(distinct iff(f.is_hospitalization and not f.is_death and not f.is_life_threatening and not f.is_disabling, f.adverse_event_report_id, null)) as is_hospitalization
            from {MARTS}.fct_adverse_events f join {MARTS}.dim_drugs d using (drug_key)
            where f.is_suspect and f.is_serious and year(f.received_date) = {int(year)}
            group by 1 order by (is_death + is_life_threatening + is_disabling + is_hospitalization) desc limit 15"""
    )
    with c2:
        st.subheader(f"Severity mix, top drugs ({year})")
        st.caption("Each report counted once, at its most severe outcome.")
        long = sev.melt("generic_name", var_name="outcome", value_name="reports")
        long["outcome"] = long["outcome"].map(SEVERITY_COLS)
        fig = px.bar(long, y="generic_name", x="reports", color="outcome", orientation="h",
                     category_orders={"generic_name": sev["generic_name"].tolist()},
                     labels={"generic_name": ""})
        fig.update_yaxes(autorange="reversed")
        st.plotly_chart(fig, width="stretch")

# --- Recalls -----------------------------------------------------------------------------
with tab_recalls:
    st.subheader("Recall risk by manufacturer and reason")
    min_year = st.slider("Recalls reported since", 2012, 2026, 2023)
    heat = run(
        f"""select m.manufacturer_name, r.recall_reason_category as reason, count(*) as recalls
            from {MARTS}.fct_recalls r join {MARTS}.dim_manufacturers m using (manufacturer_key)
            where year(r.report_date) >= {int(min_year)} group by 1, 2"""
    )
    if heat.empty:
        st.info("No recalls in that range.")
    else:
        top = heat.groupby("manufacturer_name")["recalls"].sum().nlargest(20).index
        pivot = heat[heat["manufacturer_name"].isin(top)].pivot_table(
            index="manufacturer_name", columns="reason", values="recalls", fill_value=0)
        pivot = pivot.loc[pivot.sum(axis=1).sort_values(ascending=False).index]
        fig = px.imshow(pivot, aspect="auto", color_continuous_scale="Reds", text_auto=True,
                        labels={"color": "recalls", "x": "", "y": ""})
        fig.update_layout(height=620)
        st.plotly_chart(fig, width="stretch")

    c1, c2 = st.columns(2)
    by_class = run(
        f"""select date_trunc('year', report_date) as year, recall_classification as class, count(*) as recalls
            from {MARTS}.fct_recalls where year(report_date) >= {int(min_year)} group by 1, 2 order by 1"""
    )
    with c1:
        st.subheader("Recalls by class")
        st.plotly_chart(px.bar(by_class, x="year", y="recalls", color="class",
                               color_discrete_map={"Class I": "#b2182b", "Class II": "#ef8a62", "Class III": "#fddbc7"}),
                        width="stretch")
    with c2:
        st.subheader("Latest Class I recalls")
        st.dataframe(run(
            f"""select r.report_date, m.manufacturer_name, r.recall_reason_category, r.recall_status, left(r.recall_reason, 140) as reason
                from {MARTS}.fct_recalls r join {MARTS}.dim_manufacturers m using (manufacturer_key)
                where r.is_class_i order by r.report_date desc limit 15"""),
            hide_index=True, width="stretch")

# --- Payments vs safety ------------------------------------------------------------------
with tab_conflict:
    st.subheader("Physician payments against safety signals")
    signals = run(f"select * from {MARTS}.mart_compliance_risk_signals")
    year = int(signals["program_year"].max())
    st.caption(
        f"{year} program year. Payments are CMS general payments; reports are serious FAERS reports "
        "naming the manufacturer's drugs as suspect."
    )
    signals["alert"] = signals["alert_level"].fillna("none")
    fig = px.scatter(
        signals, x="total_payments_usd", y="serious_reports", size="physicians_paid",
        color="alert", hover_name="manufacturer_name", log_x=True, log_y=True,
        color_discrete_map={"critical": "#b2182b", "watch": "#ef8a62", "none": "#9aa5b1"},
        labels={"total_payments_usd": "payments to physicians (USD)", "serious_reports": "serious reports"},
    )
    st.plotly_chart(fig, width="stretch")

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Payment concentration")
        st.caption("Share of a manufacturer's payments going to its top 10% of paid physicians.")
        top_payers = signals.nlargest(25, "total_payments_usd")
        st.plotly_chart(px.bar(top_payers.sort_values("top_decile_share"), x="top_decile_share",
                               y="manufacturer_name", orientation="h", labels={"manufacturer_name": ""}),
                        width="stretch")
    with c2:
        st.subheader("Signals by manufacturer")
        st.dataframe(
            signals[signals["is_material_payer"]].sort_values(["signals_met", "total_payments_usd"], ascending=False)
            [["manufacturer_name", "total_payments_usd", "top_decile_share", "serious_reports_h1",
              "serious_reports_h2", "class_i_recalls", "signals_met", "alert_level"]].head(40),
            hide_index=True, width="stretch")

# --- Compliance alerts -------------------------------------------------------------------
with tab_alerts:
    st.subheader("Alerts raised by the compliance agent")
    try:
        alerts = run("select created_at, manufacturer_name, analysis_year, alert_level, status, brief "
                     "from agent.compliance_alerts order by created_at desc")
    except Exception:
        alerts = pd.DataFrame()
    if alerts.empty:
        st.info("No alerts yet. Run `uv run python agent/compliance_watch.py`.")
    else:
        st.dataframe(alerts.drop(columns="brief"), hide_index=True, width="stretch")
        pick = st.selectbox("Brief", alerts["manufacturer_name"] + " (" + alerts["analysis_year"].astype(str) + ")")
        st.code(alerts.loc[(alerts["manufacturer_name"] + " (" + alerts["analysis_year"].astype(str) + ")") == pick, "brief"].iloc[0], language=None)
