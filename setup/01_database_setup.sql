-- ============================================================
-- 01_database_setup.sql
-- Creates the FINANCIAL_VARIANCE database, warehouse, and
-- Bronze / Silver / Gold schemas.
-- ============================================================

USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS FINANCE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS FINANCIAL_VARIANCE;

USE DATABASE FINANCIAL_VARIANCE;

CREATE SCHEMA IF NOT EXISTS BRONZE  COMMENT = 'Raw ingestion layer — Workday report extracts';
CREATE SCHEMA IF NOT EXISTS SILVER  COMMENT = 'Cleaned and standardized data';
CREATE SCHEMA IF NOT EXISTS GOLD    COMMENT = 'Analytics, BvA, anomaly detection, AI commentary';
