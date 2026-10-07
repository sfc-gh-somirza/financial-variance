# Finance Variance Analysis & Anomaly Detection

Budget vs. Actual analysis and AI-powered anomaly detection for finance teams, built on Snowflake with a Bronze-Silver-Gold architecture.

Based on [How We Used Cortex Code to Turn Finance Variance Analysis into a Live, Intelligent Workflow](https://www.snowflake.com/en/blog/finance-variance-analysis-workflow/).

## Architecture

```
Bronze (Raw)                Silver (Clean)              Gold (Analytics)
---------------------       ---------------------       --------------------------
RAW_COST_CENTERS       -->  COST_CENTERS_DT        -->  EXPENSE_BVA_DT
RAW_GL_JOURNAL_LINES   -->  JOURNAL_ENTRIES_DT      -->  REVENUE_BVA_DT
RAW_EXPENSE_REPORT     -->  EXPENSE_ACTUALS_DT      -->  HEADCOUNT_BVA_DT
RAW_AP_INVOICES        -->  INVOICES_DT             -->  PNL_CONSOLIDATED_DT
RAW_REVENUE            -->  REVENUE_ACTUALS_DT      -->  SUPPLIER_SPEND_SUMMARY_DT
RAW_CUSTOMER_REVENUE   -->  CUSTOMER_REVENUE_DT     -->  CUSTOMER_REVENUE_DETAIL_DT
RAW_HEADCOUNT          -->  HEADCOUNT_ACTUALS_DT    -->  SUPPLIER_SPEND_QUARTERLY_DT
RAW_EXPENSE_FORECAST   -->  EXPENSE_FORECAST_DT     -->  EXECUTIVE_KPI_DT
RAW_REVENUE_FORECAST   -->  REVENUE_FORECAST_DT     -->  ANOMALY_SCORES_DT
RAW_HEADCOUNT_FORECAST -->  HEADCOUNT_FORECAST_DT   -->  BVA_COMMENTARY (table)
```

All Silver and Gold objects are **dynamic tables** (except BVA_COMMENTARY), providing automatic lineage tracking.

## Cummins Workday Report Mapping

| Workday Report | Bronze Table | Description |
|---|---|---|
| OBGL0002 / OBGL0003 / OBGL0004 | RAW_GL_JOURNAL_LINES | General Ledger journal entries |
| Expense Category Report | RAW_EXPENSE_REPORT | Monthly expense actuals by category |
| OBAP0009 (Duplicate Sniffer) | RAW_AP_INVOICES | AP invoices — anomaly detection targets |
| OBAP0017 / OBAP0029 (Invoice Register/Status) | RAW_AP_INVOICES | Invoice lifecycle tracking |
| Supplier Spend Dashboard | SUPPLIER_SPEND_QUARTERLY_DT (Gold) | Supplier spend with QoQ comparison |
| Customer Revenue Dashboard | CUSTOMER_REVENUE_DETAIL_DT (Gold) | Customer revenue with payment trends |
| Forecast Data | RAW_EXPENSE/REVENUE/HEADCOUNT_FORECAST | Plan, Q1FC, Q2FC, Q3FC versions |

## Anomaly Detection Methods

1. **Duplicate Invoice Detection** — Matches on supplier + amount within 5-day window
2. **Unusual Amount Detection** — Z-score > 3 standard deviations from category mean
3. **Suspicious Journal Entries** — Weekend postings, unknown users, round-number large amounts
4. **Supplier Concentration Risk** — Single supplier exceeding 25% of category spend

## Setup

1. Run SQL scripts in order:
   ```
   setup/01_database_setup.sql
   setup/02_bronze_data.sql
   setup/03_silver_layer.sql
   setup/04_gold_layer.sql
   setup/05_anomaly_detection.sql
   ```

2. Wait for dynamic tables to complete first refresh (~2-3 minutes)

3. Deploy Streamlit app in Snowflake:
   - Create Streamlit App in Snowsight
   - Upload `streamlit/financial_variance_app.py` and `streamlit/environment.yml`
   - Set warehouse to `FINANCE_WH`, database/schema to `FINANCIAL_VARIANCE.GOLD`

4. (Optional) Generate AI commentary:
   ```sql
   CALL FINANCIAL_VARIANCE.GOLD.GENERATE_BVA_COMMENTARY_SP('FY2026', 'Plan');
   ```

## Cowork Dashboard

Gold views designed for Cowork executive dashboards:

- **EXECUTIVE_KPI_DT** — Scorecard tiles (revenue, expense, net income, variance counts)
- **CUSTOMER_REVENUE_DETAIL_DT** — Supports "Top customers for BC X over last 24 months"
- **SUPPLIER_SPEND_QUARTERLY_DT** — Supports "Compare supplier spend for BC X, Q1 vs Q2"

Use `{{ filter('business_code') }}` and `{{ filter('fiscal_year') }}` in tile SQL.

## AI Features

- **Variance Commentary**: `GENERATE_BVA_COMMENTARY_SP` uses `llama3.1-8b` to draft BvA explanations
- **Anomaly Explanation**: `EXPLAIN_ANOMALIES_SP` generates investigation guidance for high-severity findings
- **Analyst Override**: Dashboard supports saving analyst-edited commentary alongside AI drafts
