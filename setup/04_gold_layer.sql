-- ============================================================
-- 04_gold_layer.sql
-- Analytical Gold dynamic tables: BvA variance analysis,
-- P&L consolidation, supplier spend, and executive views.
-- ============================================================

USE DATABASE FINANCIAL_VARIANCE;
USE SCHEMA GOLD;
USE WAREHOUSE FINANCE_WH;

-- ────────────────────────────────────────────────────────────
-- 1. EXPENSE_BVA_DT — Budget vs. Actual for expenses
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE EXPENSE_BVA_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    a.ORGANIZATION,
    a.BUSINESS_CODE,
    a.EXPENSE_CATEGORY,
    f.PLANNING_VERSION,
    a.FISCAL_YEAR,
    a.MONTH,
    a.FISCAL_QUARTER,
    a.AMOUNT                                 AS ACTUAL_AMOUNT,
    f.AMOUNT                                 AS FORECAST_AMOUNT,
    a.AMOUNT - f.AMOUNT                      AS VARIANCE_AMOUNT,
    CASE WHEN f.AMOUNT != 0
         THEN ROUND((a.AMOUNT - f.AMOUNT) / ABS(f.AMOUNT) * 100, 2)
         ELSE NULL
    END                                      AS VARIANCE_PCT,
    CASE WHEN a.AMOUNT <= f.AMOUNT THEN TRUE ELSE FALSE END AS IS_FAVORABLE,
    a.IS_GAAP_ONLY,
    a.SW_SUBCATEGORY,
    cc.LEADER,
    cc.REGION
FROM SILVER.EXPENSE_ACTUALS_DT a
JOIN SILVER.EXPENSE_FORECAST_DT f
    ON  a.ORGANIZATION     = f.ORGANIZATION
    AND a.EXPENSE_CATEGORY = f.EXPENSE_CATEGORY
    AND a.FISCAL_YEAR      = f.FISCAL_YEAR
    AND a.MONTH            = f.MONTH
LEFT JOIN SILVER.COST_CENTERS_DT cc
    ON a.BUSINESS_CODE = cc.BUSINESS_CODE
    AND cc.COST_CENTER_ID = (
        SELECT MIN(COST_CENTER_ID) FROM SILVER.COST_CENTERS_DT
        WHERE BUSINESS_CODE = a.BUSINESS_CODE
    );


-- ────────────────────────────────────────────────────────────
-- 2. REVENUE_BVA_DT — Budget vs. Actual for revenue
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE REVENUE_BVA_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    a.REVENUE_CATEGORY,
    a.BUSINESS_CODE,
    f.PLANNING_VERSION,
    a.FISCAL_YEAR,
    a.MONTH,
    a.FISCAL_QUARTER,
    a.AMOUNT                                 AS ACTUAL_AMOUNT,
    f.AMOUNT                                 AS FORECAST_AMOUNT,
    a.AMOUNT - f.AMOUNT                      AS VARIANCE_AMOUNT,
    CASE WHEN f.AMOUNT != 0
         THEN ROUND((a.AMOUNT - f.AMOUNT) / ABS(f.AMOUNT) * 100, 2)
         ELSE NULL
    END                                      AS VARIANCE_PCT,
    CASE WHEN a.AMOUNT >= f.AMOUNT THEN TRUE ELSE FALSE END AS IS_FAVORABLE
FROM SILVER.REVENUE_ACTUALS_DT a
JOIN SILVER.REVENUE_FORECAST_DT f
    ON  a.REVENUE_CATEGORY = f.REVENUE_CATEGORY
    AND a.BUSINESS_CODE    = f.BUSINESS_CODE
    AND a.FISCAL_YEAR      = f.FISCAL_YEAR
    AND a.MONTH            = f.MONTH;


-- ────────────────────────────────────────────────────────────
-- 3. HEADCOUNT_BVA_DT — Headcount actual vs. plan
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE HEADCOUNT_BVA_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    a.ORGANIZATION,
    a.BUSINESS_CODE,
    f.PLANNING_VERSION,
    a.FISCAL_YEAR,
    a.MONTH,
    a.FISCAL_QUARTER,
    a.HC                     AS ACTUAL_HC,
    f.HC                     AS FORECAST_HC,
    a.HC - f.HC              AS VARIANCE_HC,
    CASE WHEN f.HC != 0
         THEN ROUND((a.HC - f.HC)::FLOAT / f.HC * 100, 2)
         ELSE NULL
    END                      AS VARIANCE_PCT
FROM SILVER.HEADCOUNT_ACTUALS_DT a
JOIN SILVER.HEADCOUNT_FORECAST_DT f
    ON  a.ORGANIZATION = f.ORGANIZATION
    AND a.FISCAL_YEAR  = f.FISCAL_YEAR
    AND a.MONTH        = f.MONTH;


-- ────────────────────────────────────────────────────────────
-- 4. PNL_CONSOLIDATED_DT — Combined P&L view
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE PNL_CONSOLIDATED_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
-- Revenue lines
SELECT
    'Revenue'              AS BVA_SECTION,
    REVENUE_CATEGORY       AS LINE_ITEM,
    BUSINESS_CODE,
    NULL                   AS ORGANIZATION,
    PLANNING_VERSION,
    FISCAL_YEAR,
    MONTH,
    FISCAL_QUARTER,
    ACTUAL_AMOUNT,
    FORECAST_AMOUNT,
    VARIANCE_AMOUNT,
    VARIANCE_PCT,
    IS_FAVORABLE
FROM GOLD.REVENUE_BVA_DT
UNION ALL
-- Expense lines (sign-flipped: favorable = under budget)
SELECT
    'Operating Expense'    AS BVA_SECTION,
    EXPENSE_CATEGORY       AS LINE_ITEM,
    BUSINESS_CODE,
    ORGANIZATION,
    PLANNING_VERSION,
    FISCAL_YEAR,
    MONTH,
    FISCAL_QUARTER,
    ACTUAL_AMOUNT,
    FORECAST_AMOUNT,
    VARIANCE_AMOUNT,
    VARIANCE_PCT,
    IS_FAVORABLE
FROM GOLD.EXPENSE_BVA_DT;


-- ────────────────────────────────────────────────────────────
-- 5. SUPPLIER_SPEND_SUMMARY_DT
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE SUPPLIER_SPEND_SUMMARY_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    j.SUPPLIER,
    j.BUSINESS_CODE,
    j.EXPENSE_CATEGORY,
    j.FISCAL_YEAR,
    j.FISCAL_QUARTER,
    j.FISCAL_MONTH,
    COUNT(*)                    AS TRANSACTION_COUNT,
    SUM(j.AMOUNT)              AS TOTAL_SPEND,
    AVG(j.AMOUNT)              AS AVG_TRANSACTION,
    MIN(j.AMOUNT)              AS MIN_TRANSACTION,
    MAX(j.AMOUNT)              AS MAX_TRANSACTION,
    -- Supplier concentration: share of total category spend
    SUM(j.AMOUNT) / NULLIF(
        SUM(SUM(j.AMOUNT)) OVER (
            PARTITION BY j.BUSINESS_CODE, j.EXPENSE_CATEGORY, j.FISCAL_YEAR, j.FISCAL_QUARTER
        ), 0) * 100            AS SPEND_SHARE_PCT
FROM SILVER.JOURNAL_ENTRIES_DT j
WHERE j.SUPPLIER IS NOT NULL
GROUP BY j.SUPPLIER, j.BUSINESS_CODE, j.EXPENSE_CATEGORY,
         j.FISCAL_YEAR, j.FISCAL_QUARTER, j.FISCAL_MONTH;


-- ────────────────────────────────────────────────────────────
-- 6. CUSTOMER_REVENUE_DETAIL_DT — for Cowork executive dashboard
--    Supports: "Top customers for BC 011 over last 24 months"
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE CUSTOMER_REVENUE_DETAIL_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    cr.CUSTOMER_NAME,
    cr.CUSTOMER_ID,
    cr.BUSINESS_CODE,
    cr.REVENUE_CATEGORY,
    cr.FISCAL_YEAR,
    cr.MONTH,
    cr.FISCAL_QUARTER,
    cr.AMOUNT                                     AS REVENUE_AMOUNT,
    cr.PAYMENT_STATUS,
    cr.DAYS_TO_PAY,
    -- Rolling 24-month total
    SUM(cr.AMOUNT) OVER (
        PARTITION BY cr.CUSTOMER_ID
        ORDER BY cr.FISCAL_YEAR, cr.MONTH
        ROWS BETWEEN 23 PRECEDING AND CURRENT ROW
    )                                             AS ROLLING_24M_REVENUE,
    -- Customer rank within business code
    RANK() OVER (
        PARTITION BY cr.BUSINESS_CODE, cr.FISCAL_YEAR, cr.FISCAL_QUARTER
        ORDER BY SUM(cr.AMOUNT) OVER (
            PARTITION BY cr.CUSTOMER_ID, cr.FISCAL_YEAR, cr.FISCAL_QUARTER
        ) DESC
    )                                             AS CUSTOMER_RANK_IN_BC,
    -- Average days to pay
    AVG(cr.DAYS_TO_PAY) OVER (
        PARTITION BY cr.CUSTOMER_ID
        ORDER BY cr.FISCAL_YEAR, cr.MONTH
        ROWS BETWEEN 5 PRECEDING AND CURRENT ROW
    )                                             AS AVG_DAYS_TO_PAY_6M,
    -- Overdue rate
    COUNT(CASE WHEN cr.PAYMENT_STATUS = 'Overdue' THEN 1 END) OVER (
        PARTITION BY cr.CUSTOMER_ID
    )::FLOAT / NULLIF(COUNT(*) OVER (PARTITION BY cr.CUSTOMER_ID), 0) * 100
                                                  AS OVERDUE_RATE_PCT
FROM SILVER.CUSTOMER_REVENUE_DT cr;


-- ────────────────────────────────────────────────────────────
-- 7. SUPPLIER_SPEND_QUARTERLY_DT — for Cowork executive dashboard
--    Supports: "Compare supplier spend BC 018, Q1 vs Q2 2026"
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE SUPPLIER_SPEND_QUARTERLY_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
WITH quarterly_spend AS (
    SELECT
        i.SUPPLIER,
        i.BUSINESS_CODE,
        i.FISCAL_YEAR,
        i.FISCAL_QUARTER,
        COUNT(*)          AS INVOICE_COUNT,
        SUM(i.AMOUNT)     AS TOTAL_SPEND,
        AVG(i.AMOUNT)     AS AVG_INVOICE_AMOUNT
    FROM SILVER.INVOICES_DT i
    WHERE i.STATUS != 'Void'
    GROUP BY i.SUPPLIER, i.BUSINESS_CODE, i.FISCAL_YEAR, i.FISCAL_QUARTER
)
SELECT
    q.*,
    LAG(q.TOTAL_SPEND) OVER (
        PARTITION BY q.SUPPLIER, q.BUSINESS_CODE
        ORDER BY q.FISCAL_YEAR, q.FISCAL_QUARTER
    )                                             AS PRIOR_QUARTER_SPEND,
    q.TOTAL_SPEND - COALESCE(LAG(q.TOTAL_SPEND) OVER (
        PARTITION BY q.SUPPLIER, q.BUSINESS_CODE
        ORDER BY q.FISCAL_YEAR, q.FISCAL_QUARTER
    ), 0)                                         AS QOQ_CHANGE,
    CASE WHEN LAG(q.TOTAL_SPEND) OVER (
            PARTITION BY q.SUPPLIER, q.BUSINESS_CODE
            ORDER BY q.FISCAL_YEAR, q.FISCAL_QUARTER
        ) != 0
         THEN ROUND(
            (q.TOTAL_SPEND - LAG(q.TOTAL_SPEND) OVER (
                PARTITION BY q.SUPPLIER, q.BUSINESS_CODE
                ORDER BY q.FISCAL_YEAR, q.FISCAL_QUARTER
            )) / ABS(LAG(q.TOTAL_SPEND) OVER (
                PARTITION BY q.SUPPLIER, q.BUSINESS_CODE
                ORDER BY q.FISCAL_YEAR, q.FISCAL_QUARTER
            )) * 100, 2)
         ELSE NULL
    END                                           AS QOQ_CHANGE_PCT,
    -- Rank suppliers by spend within BC + quarter
    RANK() OVER (
        PARTITION BY q.BUSINESS_CODE, q.FISCAL_YEAR, q.FISCAL_QUARTER
        ORDER BY q.TOTAL_SPEND DESC
    )                                             AS SPEND_RANK
FROM quarterly_spend q;


-- ────────────────────────────────────────────────────────────
-- 8. EXECUTIVE_KPI_DT — Top-level KPIs for dashboard scorecards
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE EXECUTIVE_KPI_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS
SELECT
    p.PLANNING_VERSION,
    p.FISCAL_YEAR,
    p.FISCAL_QUARTER,
    -- Revenue KPIs
    SUM(CASE WHEN p.BVA_SECTION = 'Revenue' THEN p.ACTUAL_AMOUNT ELSE 0 END) AS TOTAL_REVENUE_ACTUAL,
    SUM(CASE WHEN p.BVA_SECTION = 'Revenue' THEN p.FORECAST_AMOUNT ELSE 0 END) AS TOTAL_REVENUE_FORECAST,
    SUM(CASE WHEN p.BVA_SECTION = 'Revenue' THEN p.VARIANCE_AMOUNT ELSE 0 END) AS REVENUE_VARIANCE,
    -- Expense KPIs
    SUM(CASE WHEN p.BVA_SECTION = 'Operating Expense' THEN p.ACTUAL_AMOUNT ELSE 0 END) AS TOTAL_EXPENSE_ACTUAL,
    SUM(CASE WHEN p.BVA_SECTION = 'Operating Expense' THEN p.FORECAST_AMOUNT ELSE 0 END) AS TOTAL_EXPENSE_FORECAST,
    SUM(CASE WHEN p.BVA_SECTION = 'Operating Expense' THEN p.VARIANCE_AMOUNT ELSE 0 END) AS EXPENSE_VARIANCE,
    -- Net margin
    SUM(CASE WHEN p.BVA_SECTION = 'Revenue' THEN p.ACTUAL_AMOUNT ELSE 0 END)
    - SUM(CASE WHEN p.BVA_SECTION = 'Operating Expense' THEN p.ACTUAL_AMOUNT ELSE 0 END) AS NET_INCOME_ACTUAL,
    -- Favorable / unfavorable counts
    SUM(CASE WHEN p.IS_FAVORABLE THEN 1 ELSE 0 END)  AS FAVORABLE_LINE_COUNT,
    SUM(CASE WHEN NOT p.IS_FAVORABLE THEN 1 ELSE 0 END) AS UNFAVORABLE_LINE_COUNT
FROM GOLD.PNL_CONSOLIDATED_DT p
GROUP BY p.PLANNING_VERSION, p.FISCAL_YEAR, p.FISCAL_QUARTER;


-- ────────────────────────────────────────────────────────────
-- 9. BVA_COMMENTARY — stores AI and analyst commentary
--    (standard table — not dynamic, written by app/procedure)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE BVA_COMMENTARY (
    ANALYSIS_MONTH    DATE          NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    FISCAL_QUARTER    INT           NOT NULL,
    PLANNING_VERSION  VARCHAR(20),
    ORGANIZATION      VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10),
    EXPENSE_CATEGORY  VARCHAR(100)  NOT NULL,
    COMMENTARY        TEXT,
    SOURCE            VARCHAR(20)   NOT NULL DEFAULT 'AI',  -- 'AI' or 'Analyst'
    USER_NAME         VARCHAR(100)  NOT NULL DEFAULT 'system',
    MODIFIED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RUN_ID            VARCHAR(50)
);
