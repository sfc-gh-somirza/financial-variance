-- ============================================================
-- deploy.sql
-- Master deployment script — run this to set up everything.
-- Execute from Snowsight or SnowSQL.
-- ============================================================

-- Step 1: Database & schemas
!source setup/01_database_setup.sql;

-- Step 2: Bronze synthetic data
!source setup/02_bronze_data.sql;

-- Step 3: Silver dynamic tables
!source setup/03_silver_layer.sql;

-- Step 4: Gold analytical layer
!source setup/04_gold_layer.sql;

-- Step 5: Anomaly detection + AI procedures
!source setup/05_anomaly_detection.sql;

-- Step 6: Wait for dynamic tables to refresh
-- Dynamic tables refresh automatically. First refresh may take a few minutes.
-- Check status:
-- SELECT NAME, SCHEDULING_STATE FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
-- WHERE DATABASE_NAME = 'FINANCIAL_VARIANCE';

-- Step 7: Generate initial AI commentary (optional)
-- CALL FINANCIAL_VARIANCE.GOLD.GENERATE_BVA_COMMENTARY_SP('FY2026', 'Plan');

-- Step 8: Deploy Streamlit app
-- Run from the Snowflake UI:
--   1. Go to Streamlit > Create Streamlit App
--   2. Name: Financial_Variance_Analysis
--   3. Warehouse: FINANCE_WH
--   4. Database/Schema: FINANCIAL_VARIANCE.GOLD
--   5. Upload streamlit/financial_variance_app.py as the main file
--   6. Upload streamlit/environment.yml

-- ============================================================
-- Alternative: Run scripts individually in order
-- ============================================================
-- If !source is not supported in your client, run each file
-- in sequence:
--   1. setup/01_database_setup.sql
--   2. setup/02_bronze_data.sql
--   3. setup/03_silver_layer.sql
--   4. setup/04_gold_layer.sql
--   5. setup/05_anomaly_detection.sql

-- ============================================================
-- Verify deployment
-- ============================================================
-- Check Bronze row counts
-- SELECT 'RAW_COST_CENTERS' AS TBL, COUNT(*) AS ROWS FROM FINANCIAL_VARIANCE.BRONZE.RAW_COST_CENTERS
-- UNION ALL SELECT 'RAW_GL_JOURNAL_LINES', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_GL_JOURNAL_LINES
-- UNION ALL SELECT 'RAW_AP_INVOICES', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_AP_INVOICES
-- UNION ALL SELECT 'RAW_EXPENSE_REPORT', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_EXPENSE_REPORT
-- UNION ALL SELECT 'RAW_REVENUE', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_REVENUE
-- UNION ALL SELECT 'RAW_CUSTOMER_REVENUE', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_CUSTOMER_REVENUE
-- UNION ALL SELECT 'RAW_HEADCOUNT', COUNT(*) FROM FINANCIAL_VARIANCE.BRONZE.RAW_HEADCOUNT;

-- Check dynamic table lineage
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_GRAPH_HISTORY())
-- WHERE DATABASE_NAME = 'FINANCIAL_VARIANCE';
