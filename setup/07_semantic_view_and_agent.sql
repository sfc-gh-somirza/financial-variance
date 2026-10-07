-- ============================================================
-- 07_semantic_view_and_agent.sql
-- Creates the semantic view and Cortex Agent for ad-hoc
-- finance analysis in Cowork.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE FINANCE_WH;

-- 1. Create semantic view from YAML
-- (Run the CALL statement with the YAML inline — see deploy notes)

-- 2. Create Cortex Agent
CREATE OR REPLACE AGENT FINANCIAL_VARIANCE.GOLD.FINANCE_ANALYST_AGENT
  COMMENT = 'Ad-hoc finance analysis agent for variance deep dives, supplier spend, customer revenue, and anomaly investigation'
  PROFILE = '{"display_name": "Finance Analyst", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    tool_not_accessible: accept
    budget:
      seconds: 60
      tokens: 32000

  instructions:
    response: >
      You are a senior FP&A analyst helping finance leaders investigate budget vs. actual
      variances, supplier spend patterns, customer revenue trends, and financial anomalies.
      Be precise with numbers. Always include dollar amounts and percentages.
      When discussing variances, clarify whether they are favorable or unfavorable.
      Use business language appropriate for a CFO audience.
    orchestration: >
      For expense, revenue, or headcount variance questions, use the FinanceAnalyst tool.
      For supplier spend comparisons or customer revenue questions, also use FinanceAnalyst.
      For anomaly or fraud risk questions, use FinanceAnalyst and filter on the ANOMALIES table.
      Always generate a chart when showing trends or comparisons.
    sample_questions:
      - question: "What are the top 3 drivers of expense variance in FY2026?"
      - question: "Who are the top customers for BC 011 based on revenue over the last 24 months?"
      - question: "Compare supplier spend for BC 018 between Q1 and Q2 2026"
      - question: "Are there any high severity anomalies detected this quarter?"
      - question: "How does headcount compare to plan across all business units?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "FinanceAnalyst"
        description: "Converts natural language finance questions into SQL queries against budget vs actual, supplier spend, customer revenue, headcount, and anomaly data."
    - tool_spec:
        type: "data_to_chart"
        name: "data_to_chart"
        description: "Generates visualizations from financial data"

  tool_resources:
    FinanceAnalyst:
      semantic_view: "FINANCIAL_VARIANCE.GOLD.FINANCIAL_VARIANCE_SV"
      execution_environment:
        type: "warehouse"
        warehouse: "FINANCE_WH"
  $$;

-- 3. Grant access
GRANT SELECT ON SEMANTIC VIEW FINANCIAL_VARIANCE.GOLD.FINANCIAL_VARIANCE_SV TO ROLE FINANCE_ADMIN;
GRANT USAGE ON AGENT FINANCIAL_VARIANCE.GOLD.FINANCE_ANALYST_AGENT TO ROLE FINANCE_ADMIN;

-- Future grants
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA FINANCIAL_VARIANCE.GOLD TO ROLE FINANCE_ADMIN;
