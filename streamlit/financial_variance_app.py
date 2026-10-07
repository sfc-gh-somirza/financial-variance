"""
Financial Variance Analysis & Anomaly Detection
Streamlit-in-Snowflake application

Pages:
  1. P&L Budget vs. Actual
  2. AI Commentary
  3. Anomaly Detection
  4. Supplier Spend
  5. Revenue Dashboard
"""

import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
from snowflake.snowpark.context import get_active_session
import pandas as pd

# ── Session & Config ─────────────────────────────────────────
session = get_active_session()

DB = "FINANCIAL_VARIANCE"

def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()

def fmt_currency(val, abbrev=True):
    if val is None:
        return "N/A"
    if abbrev:
        if abs(val) >= 1_000_000:
            return f"${val/1_000_000:,.1f}M"
        if abs(val) >= 1_000:
            return f"${val/1_000:,.0f}K"
    return f"${val:,.0f}"


# ── Sidebar Navigation ──────────────────────────────────────
page = st.sidebar.radio(
    "Navigation",
    ["P&L Budget vs. Actual", "AI Commentary", "Anomaly Detection",
     "Supplier Spend", "Revenue Dashboard"],
)

# Common filters
fiscal_years = run_query(f"""
    SELECT DISTINCT FISCAL_YEAR FROM {DB}.GOLD.PNL_CONSOLIDATED_DT
    ORDER BY FISCAL_YEAR DESC
""")["FISCAL_YEAR"].tolist()

planning_versions = run_query(f"""
    SELECT DISTINCT PLANNING_VERSION FROM {DB}.GOLD.PNL_CONSOLIDATED_DT
    ORDER BY PLANNING_VERSION
""")["PLANNING_VERSION"].tolist()

selected_fy = st.sidebar.selectbox("Fiscal Year", fiscal_years, index=0)
selected_version = st.sidebar.selectbox("Planning Version", planning_versions, index=0)

business_codes = run_query(f"""
    SELECT DISTINCT BUSINESS_CODE FROM {DB}.SILVER.COST_CENTERS_DT ORDER BY BUSINESS_CODE
""")["BUSINESS_CODE"].tolist()
selected_bc = st.sidebar.selectbox("Business Code", ["All"] + business_codes)

orgs = run_query(f"""
    SELECT DISTINCT ORGANIZATION FROM {DB}.SILVER.COST_CENTERS_DT ORDER BY ORGANIZATION
""")["ORGANIZATION"].tolist()
selected_org = st.sidebar.selectbox("Organization", ["All"] + orgs)

bc_filter = f"AND BUSINESS_CODE = '{selected_bc}'" if selected_bc != "All" else ""
org_filter = f"AND ORGANIZATION = '{selected_org}'" if selected_org != "All" else ""


# ═════════════════════════════════════════════════════════════
# PAGE 1: P&L BUDGET VS. ACTUAL
# ═════════════════════════════════════════════════════════════
if page == "P&L Budget vs. Actual":
    st.title("P&L Budget vs. Actual Analysis")

    # KPI scorecards
    kpi_df = run_query(f"""
        SELECT * FROM {DB}.GOLD.EXECUTIVE_KPI_DT
        WHERE FISCAL_YEAR = '{selected_fy}'
          AND PLANNING_VERSION = '{selected_version}'
          {bc_filter} {org_filter}
    """)

    if not kpi_df.empty:
        kpi_row = kpi_df.groupby(["FISCAL_YEAR", "PLANNING_VERSION"], as_index=False).sum(numeric_only=True).iloc[0]
        c1, c2, c3, c4 = st.columns(4)
        with c1:
            st.metric("Total Revenue", fmt_currency(kpi_row["TOTAL_REVENUE_ACTUAL"]),
                       delta=fmt_currency(kpi_row["REVENUE_VARIANCE"]))
        with c2:
            st.metric("Total Expense", fmt_currency(kpi_row["TOTAL_EXPENSE_ACTUAL"]),
                       delta=fmt_currency(-kpi_row["EXPENSE_VARIANCE"]),
                       delta_color="inverse")
        with c3:
            st.metric("Net Income", fmt_currency(kpi_row["NET_INCOME_ACTUAL"]))
        with c4:
            fav = int(kpi_row["FAVORABLE_LINE_COUNT"])
            unfav = int(kpi_row["UNFAVORABLE_LINE_COUNT"])
            st.metric("Favorable / Unfavorable", f"{fav} / {unfav}")

    # View toggle
    view_mode = st.radio("View", ["Monthly", "Quarterly", "YTD"], horizontal=True)

    group_col = "MONTH" if view_mode == "Monthly" else "FISCAL_QUARTER"
    agg_suffix = "" if view_mode == "Monthly" else (
        "GROUP BY BVA_SECTION, LINE_ITEM, BUSINESS_CODE, ORGANIZATION, "
        "PLANNING_VERSION, FISCAL_YEAR, FISCAL_QUARTER, IS_FAVORABLE"
    )

    if view_mode == "YTD":
        pnl_df = run_query(f"""
            SELECT
                BVA_SECTION, LINE_ITEM, BUSINESS_CODE, ORGANIZATION,
                PLANNING_VERSION, FISCAL_YEAR,
                SUM(ACTUAL_AMOUNT)   AS ACTUAL_AMOUNT,
                SUM(FORECAST_AMOUNT) AS FORECAST_AMOUNT,
                SUM(VARIANCE_AMOUNT) AS VARIANCE_AMOUNT,
                CASE WHEN SUM(FORECAST_AMOUNT) != 0
                     THEN ROUND(SUM(VARIANCE_AMOUNT) / ABS(SUM(FORECAST_AMOUNT)) * 100, 2)
                     ELSE NULL END AS VARIANCE_PCT
            FROM {DB}.GOLD.PNL_CONSOLIDATED_DT
            WHERE FISCAL_YEAR = '{selected_fy}'
              AND PLANNING_VERSION = '{selected_version}'
              {bc_filter} {org_filter}
            GROUP BY BVA_SECTION, LINE_ITEM, BUSINESS_CODE, ORGANIZATION,
                     PLANNING_VERSION, FISCAL_YEAR
            ORDER BY BVA_SECTION, LINE_ITEM
        """)
    elif view_mode == "Quarterly":
        pnl_df = run_query(f"""
            SELECT
                BVA_SECTION, LINE_ITEM, BUSINESS_CODE, ORGANIZATION,
                PLANNING_VERSION, FISCAL_YEAR, FISCAL_QUARTER,
                SUM(ACTUAL_AMOUNT)   AS ACTUAL_AMOUNT,
                SUM(FORECAST_AMOUNT) AS FORECAST_AMOUNT,
                SUM(VARIANCE_AMOUNT) AS VARIANCE_AMOUNT,
                CASE WHEN SUM(FORECAST_AMOUNT) != 0
                     THEN ROUND(SUM(VARIANCE_AMOUNT) / ABS(SUM(FORECAST_AMOUNT)) * 100, 2)
                     ELSE NULL END AS VARIANCE_PCT
            FROM {DB}.GOLD.PNL_CONSOLIDATED_DT
            WHERE FISCAL_YEAR = '{selected_fy}'
              AND PLANNING_VERSION = '{selected_version}'
              {bc_filter} {org_filter}
            GROUP BY BVA_SECTION, LINE_ITEM, BUSINESS_CODE, ORGANIZATION,
                     PLANNING_VERSION, FISCAL_YEAR, FISCAL_QUARTER
            ORDER BY BVA_SECTION, LINE_ITEM, FISCAL_QUARTER
        """)
    else:
        pnl_df = run_query(f"""
            SELECT *
            FROM {DB}.GOLD.PNL_CONSOLIDATED_DT
            WHERE FISCAL_YEAR = '{selected_fy}'
              AND PLANNING_VERSION = '{selected_version}'
              {bc_filter} {org_filter}
            ORDER BY BVA_SECTION, LINE_ITEM, MONTH
        """)

    if not pnl_df.empty:
        # Summary table
        st.subheader("P&L Variance Summary")
        for section in pnl_df["BVA_SECTION"].unique():
            st.markdown(f"**{section}**")
            section_df = pnl_df[pnl_df["BVA_SECTION"] == section]

            if view_mode in ["YTD"]:
                summary = section_df.groupby("LINE_ITEM").agg({
                    "ACTUAL_AMOUNT": "sum",
                    "FORECAST_AMOUNT": "sum",
                    "VARIANCE_AMOUNT": "sum",
                }).reset_index()
                summary["VARIANCE_PCT"] = (summary["VARIANCE_AMOUNT"] / summary["FORECAST_AMOUNT"].abs() * 100).round(2)
                summary.columns = ["Line Item", "Actual", "Budget", "Variance $", "Variance %"]

                for col in ["Actual", "Budget", "Variance $"]:
                    summary[col] = summary[col].apply(lambda v: f"${v:,.0f}")
                summary["Variance %"] = summary["Variance %"].apply(lambda v: f"{v:.1f}%")
                st.dataframe(summary, use_container_width=True)
            else:
                st.dataframe(section_df, use_container_width=True)

        # Variance waterfall chart — always shown using YTD aggregation
        st.subheader("Variance Waterfall")
        waterfall_df = pnl_df.groupby(["BVA_SECTION", "LINE_ITEM"]).agg(
            {"VARIANCE_AMOUNT": "sum"}).reset_index()
        waterfall_df = waterfall_df.sort_values("VARIANCE_AMOUNT")

        if not waterfall_df.empty:
            fig = px.bar(waterfall_df, x="LINE_ITEM", y="VARIANCE_AMOUNT",
                         color="BVA_SECTION",
                         title="Variance by Line Item",
                         labels={"VARIANCE_AMOUNT": "Variance ($)", "LINE_ITEM": ""},
                         color_discrete_map={"Revenue": "#3498db", "Operating Expense": "#e74c3c"})
            fig.update_layout(xaxis_tickangle=-45, height=500)
            st.plotly_chart(fig, use_container_width=True)

    else:
        st.info("No data available for the selected filters.")


# ═════════════════════════════════════════════════════════════
# PAGE 2: AI COMMENTARY
# ═════════════════════════════════════════════════════════════
elif page == "AI Commentary":
    st.title("AI-Generated Variance Commentary")
    st.caption("AI drafts variance explanations for review. Toggle between AI and analyst modes.")

    # Check for existing commentary
    commentary_df = run_query(f"""
        SELECT * FROM {DB}.GOLD.BVA_COMMENTARY
        WHERE FISCAL_YEAR = '{selected_fy}'
          AND (PLANNING_VERSION = '{selected_version}' OR PLANNING_VERSION IS NULL)
          {org_filter}
        ORDER BY ORGANIZATION, EXPENSE_CATEGORY
    """)

    col_gen, col_mode = st.columns([1, 1])
    with col_gen:
        if st.button("Generate AI Commentary", type="primary"):
            with st.spinner("Generating variance commentary with AI..."):
                try:
                    session.sql(f"""
                        CALL {DB}.GOLD.GENERATE_BVA_COMMENTARY_SP(
                            '{selected_fy}', '{selected_version}'
                        )
                    """).collect()
                    st.success("Commentary generated! Refresh the page to see results.")
                except Exception as e:
                    st.error(f"Error generating commentary: {e}")

    with col_mode:
        mode = st.radio("Display Mode", ["AI Generated", "Analyst Locked"], horizontal=True)

    if not commentary_df.empty:
        filtered = commentary_df[commentary_df["SOURCE"] == ("AI" if mode == "AI Generated" else "Analyst")]
        if selected_bc != "All":
            filtered = filtered[filtered["BUSINESS_CODE"] == selected_bc]
        if selected_org != "All":
            filtered = filtered[filtered["ORGANIZATION"] == selected_org]

        if not filtered.empty:
            display_df = filtered[["ORGANIZATION", "BUSINESS_CODE", "EXPENSE_CATEGORY",
                                   "FISCAL_QUARTER", "COMMENTARY", "MODIFIED_AT"]].copy()
            display_df["COMMENTARY"] = display_df["COMMENTARY"].str.replace(
                r"^Here is a possible 2-3 sentence explanation[^:]*:\s*", "", regex=True
            )
            display_df.columns = ["Organization", "BC", "Expense Category", "Quarter", "Commentary", "Modified"]
            st.dataframe(display_df, use_container_width=True)
        else:
            st.info("No commentary for the selected mode/filters.")
    else:
        st.info("No commentary generated yet. Click 'Generate AI Commentary' to create AI drafts.")


# ═════════════════════════════════════════════════════════════
# PAGE 3: ANOMALY DETECTION
# ═════════════════════════════════════════════════════════════
elif page == "Anomaly Detection":
    st.title("Financial Anomaly Detection")
    st.caption("AI-powered detection of duplicate invoices, unusual amounts, and suspicious entries.")

    anomaly_df = run_query(f"""
        SELECT * FROM {DB}.GOLD.ANOMALY_SCORES_DT
        WHERE 1=1 {bc_filter} {org_filter}
        ORDER BY
            CASE SEVERITY WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
            AMOUNT DESC
    """)

    if not anomaly_df.empty:
        # Summary cards
        c1, c2, c3, c4 = st.columns(4)
        total = len(anomaly_df)
        high = len(anomaly_df[anomaly_df["SEVERITY"] == "HIGH"])
        med = len(anomaly_df[anomaly_df["SEVERITY"] == "MEDIUM"])
        low = len(anomaly_df[anomaly_df["SEVERITY"] == "LOW"])

        c1.metric("Total Anomalies", f"{total:,}")
        c2.metric("HIGH", f"{high:,}")
        c3.metric("MEDIUM", f"{med:,}")
        c4.metric("LOW", f"{low:,}")

        # Filter by type and severity
        col_type, col_sev = st.columns(2)
        with col_type:
            anom_types = ["All"] + anomaly_df["ANOMALY_TYPE"].unique().tolist()
            sel_type = st.selectbox("Anomaly Type", anom_types)
        with col_sev:
            sel_sev = st.selectbox("Severity", ["All", "HIGH", "MEDIUM", "LOW"])

        filtered = anomaly_df.copy()
        if sel_type != "All":
            filtered = filtered[filtered["ANOMALY_TYPE"] == sel_type]
        if sel_sev != "All":
            filtered = filtered[filtered["SEVERITY"] == sel_sev]

        st.subheader(f"Anomalies ({len(filtered):,} results)")
        st.dataframe(
            filtered[["ANOMALY_TYPE", "SEVERITY", "SOURCE_ID", "BUSINESS_CODE",
                       "SUPPLIER", "AMOUNT", "DESCRIPTION"]],
            use_container_width=True,
        )

        # Chart: anomalies by type — compute counts in SQL to avoid Decimal type issues
        st.subheader("Anomaly Distribution")
        type_counts = run_query(f"""
            SELECT ANOMALY_TYPE, SEVERITY, COUNT(*)::INT AS CNT
            FROM {DB}.GOLD.ANOMALY_SCORES_DT
            WHERE 1=1 {bc_filter} {org_filter}
            GROUP BY ANOMALY_TYPE, SEVERITY
            ORDER BY ANOMALY_TYPE, SEVERITY
        """)
        if not type_counts.empty:
            fig = go.Figure()
            colors = {"HIGH": "#e74c3c", "MEDIUM": "#f39c12", "LOW": "#3498db"}
            for sev in type_counts["SEVERITY"].unique():
                sev_df = type_counts[type_counts["SEVERITY"] == sev]
                fig.add_trace(go.Bar(
                    x=[str(v) for v in sev_df["ANOMALY_TYPE"]],
                    y=[int(v) for v in sev_df["CNT"]],
                    name=str(sev),
                    marker_color=colors.get(str(sev), "#95a5a6"),
                ))
            fig.update_layout(title="Anomalies by Type and Severity",
                              barmode="group", xaxis_title="Type", yaxis_title="Count")
            st.plotly_chart(fig, use_container_width=True)

        # AI explanation for high-severity
        st.subheader("AI Investigation")
        if st.button("Generate AI Explanations for HIGH Severity"):
            with st.spinner("Running AI analysis on high-severity anomalies..."):
                try:
                    explanations = run_query(f"CALL {DB}.GOLD.EXPLAIN_ANOMALIES_SP()")
                    for _, row in explanations.iterrows():
                        st.markdown(f"**{row['SOURCE_ID']}**: {row['AI_EXPLANATION']}")
                except Exception as e:
                    st.error(f"Error: {e}")
    else:
        st.info("No anomalies detected for the selected filters.")


# ═════════════════════════════════════════════════════════════
# PAGE 4: SUPPLIER SPEND
# ═════════════════════════════════════════════════════════════
elif page == "Supplier Spend":
    st.title("Supplier Spend Analysis")

    # Top suppliers by spend
    supplier_df = run_query(f"""
        SELECT
            SUPPLIER,
            BUSINESS_CODE,
            FISCAL_YEAR,
            FISCAL_QUARTER,
            TOTAL_SPEND,
            PRIOR_QUARTER_SPEND,
            QOQ_CHANGE,
            QOQ_CHANGE_PCT,
            INVOICE_COUNT,
            SPEND_RANK
        FROM {DB}.GOLD.SUPPLIER_SPEND_QUARTERLY_DT
        WHERE FISCAL_YEAR = '{selected_fy}'
          {bc_filter} {org_filter}
        ORDER BY TOTAL_SPEND DESC
        LIMIT 50
    """)

    if not supplier_df.empty:
        # Top 10 bar chart
        top10 = supplier_df.head(10)
        fig = px.bar(top10, x="SUPPLIER", y="TOTAL_SPEND", color="BUSINESS_CODE",
                     title="Top 10 Suppliers by Spend",
                     labels={"TOTAL_SPEND": "Total Spend ($)"})
        fig.update_layout(xaxis_tickangle=-45)
        st.plotly_chart(fig, use_container_width=True)

        # QoQ comparison
        st.subheader("Quarter-over-Quarter Spend Changes")
        qoq_df = supplier_df[supplier_df["QOQ_CHANGE"].notna()].sort_values("QOQ_CHANGE", ascending=False).head(15)
        if not qoq_df.empty:
            fig2 = px.bar(qoq_df, x="SUPPLIER", y="QOQ_CHANGE", color="QOQ_CHANGE",
                          color_continuous_scale=["#e74c3c", "#f5f5f5", "#2ecc71"],
                          title="Largest QoQ Spend Changes",
                          labels={"QOQ_CHANGE": "QoQ Change ($)"})
            fig2.update_layout(xaxis_tickangle=-45)
            st.plotly_chart(fig2, use_container_width=True)

        # Full table
        st.subheader("Supplier Detail")
        st.dataframe(supplier_df, use_container_width=True)
    else:
        st.info("No supplier spend data for the selected filters.")


# ═════════════════════════════════════════════════════════════
# PAGE 5: REVENUE DASHBOARD
# ═════════════════════════════════════════════════════════════
elif page == "Revenue Dashboard":
    st.title("Revenue Dashboard")

    # Revenue BvA
    rev_df = run_query(f"""
        SELECT
            REVENUE_CATEGORY, BUSINESS_CODE, FISCAL_YEAR, MONTH, FISCAL_QUARTER,
            ACTUAL_AMOUNT, FORECAST_AMOUNT, VARIANCE_AMOUNT, VARIANCE_PCT, IS_FAVORABLE
        FROM {DB}.GOLD.REVENUE_BVA_DT
        WHERE FISCAL_YEAR = '{selected_fy}'
          AND PLANNING_VERSION = '{selected_version}'
          {bc_filter} {org_filter}
        ORDER BY REVENUE_CATEGORY, MONTH
    """)

    if not rev_df.empty:
        # Revenue trend
        monthly_rev = rev_df.groupby("MONTH").agg(
            {"ACTUAL_AMOUNT": "sum", "FORECAST_AMOUNT": "sum"}).reset_index()
        fig = go.Figure()
        fig.add_trace(go.Scatter(x=monthly_rev["MONTH"], y=monthly_rev["ACTUAL_AMOUNT"],
                                 name="Actual", mode="lines+markers", line=dict(color="#2ecc71")))
        fig.add_trace(go.Scatter(x=monthly_rev["MONTH"], y=monthly_rev["FORECAST_AMOUNT"],
                                 name="Budget", mode="lines+markers", line=dict(color="#3498db", dash="dash")))
        fig.update_layout(title="Monthly Revenue: Actual vs. Budget",
                          xaxis_title="Month", yaxis_title="Revenue ($)")
        st.plotly_chart(fig, use_container_width=True)

        # Revenue by category
        cat_rev = rev_df.groupby("REVENUE_CATEGORY").agg(
            {"ACTUAL_AMOUNT": "sum", "VARIANCE_AMOUNT": "sum"}).reset_index()
        fig2 = px.bar(cat_rev, x="REVENUE_CATEGORY", y="ACTUAL_AMOUNT",
                      title="Revenue by Category (YTD)",
                      labels={"ACTUAL_AMOUNT": "Revenue ($)"})
        st.plotly_chart(fig2, use_container_width=True)

    # Top Customers
    st.subheader("Top Customers")
    cust_df = run_query(f"""
        SELECT
            CUSTOMER_NAME, BUSINESS_CODE, REVENUE_CATEGORY,
            SUM(REVENUE_AMOUNT) AS TOTAL_REVENUE,
            AVG(DAYS_TO_PAY) AS AVG_DAYS_TO_PAY,
            COUNT(CASE WHEN PAYMENT_STATUS = 'Overdue' THEN 1 END)::FLOAT
                / NULLIF(COUNT(*), 0) * 100 AS OVERDUE_RATE
        FROM {DB}.GOLD.CUSTOMER_REVENUE_DETAIL_DT
        WHERE FISCAL_YEAR = '{selected_fy}'
          {bc_filter} {org_filter}
        GROUP BY CUSTOMER_NAME, BUSINESS_CODE, REVENUE_CATEGORY
        ORDER BY TOTAL_REVENUE DESC
        LIMIT 20
    """)

    if not cust_df.empty:
        st.dataframe(cust_df, use_container_width=True)
    else:
        st.info("No customer revenue data for the selected filters.")
