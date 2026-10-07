-- ============================================================
-- 05_anomaly_detection.sql
-- Anomaly detection pipeline: duplicate invoices, unusual
-- amounts, suspicious journal entries, supplier concentration.
-- AI-generated explanations via Cortex COMPLETE.
-- ============================================================

USE DATABASE FINANCIAL_VARIANCE;
USE SCHEMA GOLD;
USE WAREHOUSE FINANCE_WH;

-- ────────────────────────────────────────────────────────────
-- 1. ANOMALY_SCORES_DT — Multi-method anomaly detection
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DYNAMIC TABLE ANOMALY_SCORES_DT
    TARGET_LAG = '1 hour'
    WAREHOUSE  = FINANCE_WH
    AS

-- Method 1: Duplicate Invoice Detection
SELECT
    'DUPLICATE_INVOICE'                        AS ANOMALY_TYPE,
    a.INVOICE_ID                               AS SOURCE_ID,
    'INVOICES_DT'                              AS SOURCE_TABLE,
    a.INVOICE_DATE                             AS EVENT_DATE,
    a.BUSINESS_CODE,
    a.AMOUNT,
    CASE
        WHEN a.INVOICE_NUMBER = b.INVOICE_NUMBER AND a.AMOUNT = b.AMOUNT THEN 'HIGH'
        WHEN a.SUPPLIER = b.SUPPLIER AND a.AMOUNT = b.AMOUNT THEN 'MEDIUM'
        ELSE 'LOW'
    END                                        AS SEVERITY,
    'Potential duplicate: Invoice ' || a.INVOICE_NUMBER
        || ' matches ' || b.INVOICE_NUMBER
        || ' (Supplier: ' || a.SUPPLIER
        || ', Amount: $' || TO_VARCHAR(a.AMOUNT, '999,999,999.99')
        || ', Date diff: ' || DATEDIFF('day', a.INVOICE_DATE, b.INVOICE_DATE) || ' days)'
                                               AS DESCRIPTION,
    a.SUPPLIER,
    a.COST_CENTER_ID,
    NULL::FLOAT                                AS ZSCORE
FROM SILVER.INVOICES_DT a
JOIN SILVER.INVOICES_DT b
    ON  a.INVOICE_ID != b.INVOICE_ID
    AND a.INVOICE_ID < b.INVOICE_ID  -- avoid duplicate pairs
    AND a.SUPPLIER = b.SUPPLIER
    AND a.AMOUNT = b.AMOUNT
    AND ABS(DATEDIFF('day', a.INVOICE_DATE, b.INVOICE_DATE)) <= 5

UNION ALL

-- Method 2: Unusual Journal Entry Amounts (Z-Score)
SELECT
    'UNUSUAL_AMOUNT'                           AS ANOMALY_TYPE,
    j.JOURNAL_ID                               AS SOURCE_ID,
    'JOURNAL_ENTRIES_DT'                       AS SOURCE_TABLE,
    j.ACCOUNTING_DATE                          AS EVENT_DATE,
    j.BUSINESS_CODE,
    j.AMOUNT,
    CASE
        WHEN ABS(stats.zscore) > 4 THEN 'HIGH'
        WHEN ABS(stats.zscore) > 3 THEN 'MEDIUM'
        ELSE 'LOW'
    END                                        AS SEVERITY,
    'Unusual amount: $' || TO_VARCHAR(j.AMOUNT, '999,999,999.99')
        || ' in ' || j.EXPENSE_CATEGORY
        || ' (Z-score: ' || ROUND(stats.zscore, 2) || ')'
        || ' - Category avg: $' || TO_VARCHAR(stats.cat_avg, '999,999,999.99')
                                               AS DESCRIPTION,
    j.SUPPLIER,
    j.COST_CENTER_ID,
    stats.zscore                               AS ZSCORE
FROM SILVER.JOURNAL_ENTRIES_DT j
JOIN (
    SELECT
        JOURNAL_ID,
        EXPENSE_CATEGORY,
        AMOUNT,
        AVG(AMOUNT) OVER (PARTITION BY EXPENSE_CATEGORY) AS cat_avg,
        STDDEV(AMOUNT) OVER (PARTITION BY EXPENSE_CATEGORY) AS cat_stddev,
        CASE WHEN STDDEV(AMOUNT) OVER (PARTITION BY EXPENSE_CATEGORY) > 0
             THEN (AMOUNT - AVG(AMOUNT) OVER (PARTITION BY EXPENSE_CATEGORY))
                  / STDDEV(AMOUNT) OVER (PARTITION BY EXPENSE_CATEGORY)
             ELSE 0
        END AS zscore
    FROM SILVER.JOURNAL_ENTRIES_DT
) stats ON j.JOURNAL_ID = stats.JOURNAL_ID
WHERE ABS(stats.zscore) > 3

UNION ALL

-- Method 3: Suspicious Journal Entry Patterns
SELECT
    'SUSPICIOUS_ENTRY'                         AS ANOMALY_TYPE,
    j.JOURNAL_ID                               AS SOURCE_ID,
    'JOURNAL_ENTRIES_DT'                       AS SOURCE_TABLE,
    j.ACCOUNTING_DATE                          AS EVENT_DATE,
    j.BUSINESS_CODE,
    j.AMOUNT,
    CASE
        WHEN j.IS_WEEKEND AND j.CREATED_BY = 'unknown_user' THEN 'HIGH'
        WHEN j.IS_WEEKEND THEN 'MEDIUM'
        WHEN MOD(j.AMOUNT, 1000) = 0 AND j.AMOUNT > 50000 THEN 'MEDIUM'
        ELSE 'LOW'
    END                                        AS SEVERITY,
    CASE
        WHEN j.IS_WEEKEND
            THEN 'Weekend posting on ' || j.DAY_OF_WEEK || ' by ' || j.CREATED_BY
        WHEN MOD(j.AMOUNT, 1000) = 0 AND j.AMOUNT > 50000
            THEN 'Suspiciously round amount: $' || TO_VARCHAR(j.AMOUNT, '999,999,999')
        WHEN j.CREATED_BY = 'unknown_user'
            THEN 'Entry by unrecognized user: ' || j.CREATED_BY
        ELSE 'Multiple risk signals'
    END                                        AS DESCRIPTION,
    j.SUPPLIER,
    j.COST_CENTER_ID,
    NULL::FLOAT                                AS ZSCORE
FROM SILVER.JOURNAL_ENTRIES_DT j
WHERE j.IS_WEEKEND = TRUE
   OR (MOD(j.AMOUNT, 1000) = 0 AND j.AMOUNT > 50000)
   OR j.CREATED_BY = 'unknown_user'

UNION ALL

-- Method 4: Supplier Concentration Risk
SELECT
    'SUPPLIER_CONCENTRATION'                   AS ANOMALY_TYPE,
    s.SUPPLIER || '|' || s.FISCAL_YEAR || 'Q' || s.FISCAL_QUARTER AS SOURCE_ID,
    'SUPPLIER_SPEND_SUMMARY_DT'                AS SOURCE_TABLE,
    NULL::DATE                                 AS EVENT_DATE,
    s.BUSINESS_CODE,
    s.TOTAL_SPEND                              AS AMOUNT,
    CASE
        WHEN s.SPEND_SHARE_PCT > 40 THEN 'HIGH'
        WHEN s.SPEND_SHARE_PCT > 25 THEN 'MEDIUM'
        ELSE 'LOW'
    END                                        AS SEVERITY,
    'Supplier ' || s.SUPPLIER || ' accounts for '
        || ROUND(s.SPEND_SHARE_PCT, 1) || '% of '
        || s.EXPENSE_CATEGORY || ' spend in ' || s.BUSINESS_CODE
        || ' (' || s.FISCAL_YEAR || ' Q' || s.FISCAL_QUARTER || ')'
                                               AS DESCRIPTION,
    s.SUPPLIER,
    NULL                                       AS COST_CENTER_ID,
    NULL::FLOAT                                AS ZSCORE
FROM GOLD.SUPPLIER_SPEND_SUMMARY_DT s
WHERE s.SPEND_SHARE_PCT > 25;


-- ────────────────────────────────────────────────────────────
-- 2. EXPLAIN_ANOMALIES_SP — AI explanation for high-severity
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE EXPLAIN_ANOMALIES_SP()
RETURNS TABLE (SOURCE_ID VARCHAR, AI_EXPLANATION VARCHAR)
LANGUAGE SQL
AS
BEGIN
    LET res RESULTSET := (
        SELECT
            SOURCE_ID,
            SNOWFLAKE.CORTEX.COMPLETE(
                'llama3.1-8b',
                'You are a financial auditor. Explain this anomaly finding in 2-3 sentences. '
                || 'Include what the risk is, what investigation steps the finance team should take, '
                || 'and whether this is likely a process error, data quality issue, or potential fraud risk. '
                || 'Anomaly: ' || DESCRIPTION
            )::VARCHAR AS AI_EXPLANATION
        FROM GOLD.ANOMALY_SCORES_DT
        WHERE SEVERITY = 'HIGH'
        LIMIT 50
    );
    RETURN TABLE(res);
END;


-- ────────────────────────────────────────────────────────────
-- 3. GENERATE_BVA_COMMENTARY_SP — AI variance commentary
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE GENERATE_BVA_COMMENTARY_SP(
    P_FISCAL_YEAR VARCHAR,
    P_PLANNING_VERSION VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
BEGIN
    INSERT INTO GOLD.BVA_COMMENTARY
        (ANALYSIS_MONTH, FISCAL_YEAR, FISCAL_QUARTER, PLANNING_VERSION,
         ORGANIZATION, BUSINESS_CODE, EXPENSE_CATEGORY, COMMENTARY,
         SOURCE, USER_NAME, MODIFIED_AT, RUN_ID)
    SELECT
        CURRENT_DATE(),
        bva.FISCAL_YEAR,
        bva.FISCAL_QUARTER,
        bva.PLANNING_VERSION,
        bva.ORGANIZATION,
        bva.BUSINESS_CODE,
        bva.EXPENSE_CATEGORY,
        SNOWFLAKE.CORTEX.COMPLETE(
            'llama3.1-8b',
            'You are a corporate FP&A analyst writing budget vs actual commentary for leadership. '
            || 'Write exactly 2-3 sentences explaining this variance. Be specific about drivers. '
            || 'Do NOT include any preamble, introduction, or phrases like "Here is" — start directly with the explanation. '
            || 'Context: ' || bva.ORGANIZATION || ' - ' || bva.EXPENSE_CATEGORY
            || '. Actual: $' || TO_VARCHAR(SUM(bva.ACTUAL_AMOUNT), '999,999,999')
            || ', Budget: $' || TO_VARCHAR(SUM(bva.FORECAST_AMOUNT), '999,999,999')
            || ', Variance: $' || TO_VARCHAR(SUM(bva.VARIANCE_AMOUNT), '999,999,999')
            || ' (' || ROUND(AVG(bva.VARIANCE_PCT), 1) || '%). '
            || CASE WHEN AVG(bva.VARIANCE_PCT) > 0
                    THEN 'This is an unfavorable overspend.'
                    ELSE 'This is a favorable underspend.'
               END
        )::VARCHAR,
        'AI',
        'system',
        CURRENT_TIMESTAMP(),
        'RUN-' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS')
    FROM GOLD.EXPENSE_BVA_DT bva
    WHERE bva.FISCAL_YEAR = :P_FISCAL_YEAR
      AND bva.PLANNING_VERSION = :P_PLANNING_VERSION
      AND ABS(bva.VARIANCE_PCT) > 5  -- only comment on material variances
    GROUP BY bva.FISCAL_YEAR, bva.FISCAL_QUARTER, bva.PLANNING_VERSION,
             bva.ORGANIZATION, bva.BUSINESS_CODE, bva.EXPENSE_CATEGORY;

    RETURN 'Commentary generated for ' || :P_FISCAL_YEAR || ' / ' || :P_PLANNING_VERSION;
END;
