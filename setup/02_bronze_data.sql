-- ============================================================
-- 02_bronze_data.sql
-- Generates synthetic Bronze-layer data modeled on Cummins
-- Workday reports (OBGL, OBAP, Expense Category, Forecasts).
-- ============================================================

USE DATABASE FINANCIAL_VARIANCE;
USE SCHEMA BRONZE;
USE WAREHOUSE FINANCE_WH;

-- ────────────────────────────────────────────────────────────
-- 1. RAW_COST_CENTERS  (dimension — ~30 rows)
--    Maps to: Workday Cost Center Hierarchy
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_COST_CENTERS (
    COST_CENTER_ID    VARCHAR(10)   NOT NULL,
    COST_CENTER_NAME  VARCHAR(100)  NOT NULL,
    ORGANIZATION      VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    LEADER            VARCHAR(100),
    REGION            VARCHAR(50),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_COST_CENTERS (COST_CENTER_ID, COST_CENTER_NAME, ORGANIZATION, BUSINESS_CODE, LEADER, REGION)
VALUES
-- Engine Business (BC 011)
('CC-1001', 'Engine Engineering',        'Engine Business',      'BC 011', 'James Morrison',   'North America'),
('CC-1002', 'Engine Manufacturing',      'Engine Business',      'BC 011', 'Sarah Chen',       'North America'),
('CC-1003', 'Engine Sales',              'Engine Business',      'BC 011', 'Robert Kim',       'North America'),
('CC-1004', 'Engine Quality',            'Engine Business',      'BC 011', 'Diana Patel',      'EMEA'),
('CC-1005', 'Engine Aftermarket',        'Engine Business',      'BC 011', 'Michael Torres',   'North America'),
-- Components (BC 018)
('CC-2001', 'Components Engineering',    'Components',           'BC 018', 'Lisa Wang',        'North America'),
('CC-2002', 'Components Manufacturing',  'Components',           'BC 018', 'David Johnson',    'EMEA'),
('CC-2003', 'Components Supply Chain',   'Components',           'BC 018', 'Amanda Foster',    'APAC'),
('CC-2004', 'Turbo Technologies',        'Components',           'BC 018', 'Raj Kapoor',       'APAC'),
-- Distribution (BC 025)
('CC-3001', 'Distribution Operations',   'Distribution',         'BC 025', 'Karen Mitchell',   'North America'),
('CC-3002', 'Distribution Sales',        'Distribution',         'BC 025', 'Thomas Wright',    'North America'),
('CC-3003', 'Distribution Logistics',    'Distribution',         'BC 025', 'Jennifer Lee',     'EMEA'),
-- Power Systems (BC 032)
('CC-4001', 'Power Systems Engineering', 'Power Systems',        'BC 032', 'William Davis',    'North America'),
('CC-4002', 'Power Systems Manufacturing','Power Systems',       'BC 032', 'Patricia Brown',   'North America'),
('CC-4003', 'Power Gen Sales',           'Power Systems',        'BC 032', 'Steven Clark',     'EMEA'),
('CC-4004', 'Power Gen Service',         'Power Systems',        'BC 032', 'Nancy Martinez',   'APAC'),
-- New Power (BC 040)
('CC-5001', 'Electrification R&D',       'New Power',            'BC 040', 'Andrew Yang',      'North America'),
('CC-5002', 'Hydrogen Technology',        'New Power',            'BC 040', 'Emily Zhang',      'EMEA'),
('CC-5003', 'Battery Systems',            'New Power',            'BC 040', 'Carlos Rivera',    'North America'),
-- Corporate (BC 050)
('CC-6001', 'Corporate Finance',          'Corporate',            'BC 050', 'Susan Miller',     'North America'),
('CC-6002', 'Corporate IT',              'Corporate',            'BC 050', 'Brian Taylor',     'North America'),
('CC-6003', 'Corporate HR',              'Corporate',            'BC 050', 'Michelle Anderson','North America'),
('CC-6004', 'Legal & Compliance',         'Corporate',            'BC 050', 'Daniel Harris',    'North America'),
('CC-6005', 'Corporate Marketing',        'Corporate',            'BC 050', 'Laura Wilson',     'North America'),
('CC-6006', 'Executive Office',           'Corporate',            'BC 050', 'Richard Thompson', 'North America');


-- ────────────────────────────────────────────────────────────
-- 2. RAW_GL_JOURNAL_LINES  (~60K rows)
--    Maps to: Workday OBGL0002 / OBGL0003 / OBGL0004
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_GL_JOURNAL_LINES (
    JOURNAL_ID        VARCHAR(20),
    LINE_NUMBER       INT,
    COST_CENTER_ID    VARCHAR(10)   NOT NULL,
    EXPENSE_CATEGORY  VARCHAR(100)  NOT NULL,
    LEDGER_ACCOUNT    VARCHAR(50),
    ACCOUNTING_DATE   DATE          NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    LINE_MEMO         VARCHAR(500),
    SPEND_CATEGORY    VARCHAR(100),
    SUPPLIER          VARCHAR(200),
    EMPLOYEE          VARCHAR(100),
    SOURCE            VARCHAR(50),
    CREATED_BY        VARCHAR(100),
    BUSINESS_CODE     VARCHAR(10),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Generate journal entries using SQL generator
INSERT INTO RAW_GL_JOURNAL_LINES
WITH
date_range AS (
    SELECT DATEADD('day', SEQ4(), '2024-07-01'::DATE) AS dt
    FROM TABLE(GENERATOR(ROWCOUNT => 730))  -- ~2 years of dates
),
cost_centers AS (
    SELECT COST_CENTER_ID, BUSINESS_CODE, ORGANIZATION
    FROM RAW_COST_CENTERS
),
categories AS (
    SELECT column1 AS expense_category, column2 AS base_amount, column3 AS ledger_acct
    FROM VALUES
        ('Compensation & Benefits',  85000, '6100'),
        ('Cloud Infrastructure',     25000, '6200'),
        ('Travel & Entertainment',    8000, '6300'),
        ('Professional Services',    15000, '6400'),
        ('Software Licenses',        12000, '6500'),
        ('Facilities & Occupancy',   20000, '6600'),
        ('Marketing & Events',        9000, '6700'),
        ('R&D Materials',            18000, '6800'),
        ('Depreciation',             10000, '6900'),
        ('Insurance',                 5000, '7000'),
        ('Utilities',                 3000, '7100'),
        ('Training & Development',    4000, '7200')
),
suppliers AS (
    SELECT column1 AS supplier_name
    FROM VALUES
        ('Bosch Automotive'),('Continental AG'),('BorgWarner Inc'),
        ('Eaton Corporation'),('Delphi Technologies'),('Mahle GmbH'),
        ('Denso Corporation'),('ZF Friedrichshafen'),('Honeywell Turbo'),
        ('Cummins Filtration'),('Fleetguard'),('Holset Engineering'),
        ('AWS'),('Microsoft Azure'),('Salesforce'),('SAP SE'),
        ('Deloitte Consulting'),('McKinsey & Company'),('Accenture'),
        ('KPMG Advisory'),('PwC Advisory'),('EY Consulting'),
        ('Hilton Hotels'),('United Airlines'),('American Express'),
        ('Aramark Services'),('JLL Property'),('CBRE Group'),
        ('Houghton International'),('Castrol Industrial'),
        ('Parker Hannifin'),('Cummins Turbo Tech')
),
numbered_suppliers AS (
    SELECT supplier_name, ROW_NUMBER() OVER (ORDER BY supplier_name) AS sup_rn,
           COUNT(*) OVER () AS total_suppliers
    FROM suppliers
),
base_data AS (
    SELECT
        d.dt,
        cc.COST_CENTER_ID,
        cc.BUSINESS_CODE,
        cc.ORGANIZATION,
        c.expense_category,
        c.base_amount,
        c.ledger_acct,
        UNIFORM(1, 32, RANDOM()) AS supplier_idx,
        ROW_NUMBER() OVER (ORDER BY d.dt, cc.COST_CENTER_ID, c.expense_category) AS row_num
    FROM date_range d
    CROSS JOIN cost_centers cc
    CROSS JOIN categories c
    WHERE DAYOFWEEK(d.dt) NOT IN (0, 6)  -- weekdays only
      AND UNIFORM(1, 100, RANDOM()) <= 3  -- ~3% sampling to get ~60K rows
)
SELECT
    'JE-' || LPAD(row_num::VARCHAR, 7, '0') AS journal_id,
    UNIFORM(1, 5, RANDOM()) AS line_number,
    b.COST_CENTER_ID,
    b.expense_category,
    b.ledger_acct || '-' || LPAD(UNIFORM(100, 999, RANDOM())::VARCHAR, 3, '0') AS ledger_account,
    b.dt AS accounting_date,
    ROUND(b.base_amount * (0.5 + UNIFORM(0, 100, RANDOM()) / 100.0) *
          CASE WHEN MONTH(b.dt) IN (3, 6, 9, 12) THEN 1.3 ELSE 1.0 END, 2) AS amount,
    CASE UNIFORM(1, 8, RANDOM())
        WHEN 1 THEN 'Monthly recurring charge'
        WHEN 2 THEN 'Purchase order fulfillment'
        WHEN 3 THEN 'Service contract payment'
        WHEN 4 THEN 'Capital expenditure allocation'
        WHEN 5 THEN 'Accrual reversal'
        WHEN 6 THEN 'Intercompany transfer'
        WHEN 7 THEN 'Vendor invoice payment'
        WHEN 8 THEN 'Period-end adjustment'
    END AS line_memo,
    b.expense_category AS spend_category,
    s.supplier_name AS supplier,
    CASE WHEN b.expense_category = 'Compensation & Benefits'
         THEN 'EMP-' || LPAD(UNIFORM(1000, 9999, RANDOM())::VARCHAR, 4, '0')
         ELSE NULL
    END AS employee,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'Workday GL'
        WHEN 2 THEN 'Manual Journal'
        WHEN 3 THEN 'AP Integration'
        WHEN 4 THEN 'Payroll System'
    END AS source,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'system_batch'
        WHEN 2 THEN 'j.morrison'
        WHEN 3 THEN 's.chen'
        WHEN 4 THEN 'finance_bot'
        WHEN 5 THEN 'r.kim'
    END AS created_by,
    b.BUSINESS_CODE,
    CURRENT_TIMESTAMP() AS loaded_at
FROM base_data b
LEFT JOIN numbered_suppliers s
    ON MOD(b.supplier_idx, s.total_suppliers) + 1 = s.sup_rn;


-- ────────────────────────────────────────────────────────────
-- 3. RAW_EXPENSE_REPORT  (~8K rows)
--    Maps to: Workday Expense Category Report
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_EXPENSE_REPORT (
    ORGANIZATION      VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    EXPENSE_CATEGORY  VARCHAR(100)  NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    IS_GAAP_ONLY      BOOLEAN       DEFAULT FALSE,
    SW_SUBCATEGORY    VARCHAR(100),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_EXPENSE_REPORT
WITH orgs AS (
    SELECT DISTINCT ORGANIZATION, BUSINESS_CODE FROM RAW_COST_CENTERS
),
categories AS (
    SELECT column1 AS expense_category, column2 AS monthly_base
    FROM VALUES
        ('Compensation & Benefits',  4200000),
        ('Cloud Infrastructure',      980000),
        ('Travel & Entertainment',    320000),
        ('Professional Services',     650000),
        ('Software Licenses',         480000),
        ('Facilities & Occupancy',    750000),
        ('Marketing & Events',        380000),
        ('R&D Materials',             820000),
        ('Depreciation',              420000),
        ('Insurance',                 180000),
        ('Utilities',                 120000),
        ('Training & Development',    150000)
),
fiscal_months AS (
    SELECT column1 AS fiscal_year, column2 AS month_num
    FROM VALUES
        ('FY2025', 1),('FY2025', 2),('FY2025', 3),('FY2025', 4),('FY2025', 5),('FY2025', 6),
        ('FY2025', 7),('FY2025', 8),('FY2025', 9),('FY2025',10),('FY2025',11),('FY2025',12),
        ('FY2026', 1),('FY2026', 2),('FY2026', 3),('FY2026', 4),('FY2026', 5),('FY2026', 6),
        ('FY2026', 7),('FY2026', 8),('FY2026', 9),('FY2026',10),('FY2026',11),('FY2026',12)
)
SELECT
    o.ORGANIZATION,
    o.BUSINESS_CODE,
    c.expense_category,
    fm.fiscal_year,
    fm.month_num AS month,
    ROUND(
        c.monthly_base
        * CASE o.ORGANIZATION
            WHEN 'Engine Business' THEN 0.30
            WHEN 'Components'      THEN 0.20
            WHEN 'Distribution'    THEN 0.15
            WHEN 'Power Systems'   THEN 0.18
            WHEN 'New Power'       THEN 0.10
            WHEN 'Corporate'       THEN 0.07
          END
        * (0.85 + UNIFORM(0, 30, RANDOM()) / 100.0)
        * CASE WHEN fm.month_num IN (3, 6, 9, 12) THEN 1.15 ELSE 1.0 END
        * CASE WHEN fm.fiscal_year = 'FY2026' THEN 1.05 ELSE 1.0 END
    , 2) AS amount,
    FALSE AS is_gaap_only,
    CASE WHEN c.expense_category = 'Cloud Infrastructure'
         THEN CASE UNIFORM(1, 3, RANDOM())
                WHEN 1 THEN 'Compute' WHEN 2 THEN 'Storage' WHEN 3 THEN 'Networking'
              END
         ELSE NULL
    END AS sw_subcategory,
    CURRENT_TIMESTAMP() AS loaded_at
FROM orgs o
CROSS JOIN categories c
CROSS JOIN fiscal_months fm;


-- ────────────────────────────────────────────────────────────
-- 4. RAW_AP_INVOICES  (~5K rows with seeded anomalies)
--    Maps to: Workday OBAP0009 / OBAP0017 / OBAP0029
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_AP_INVOICES (
    INVOICE_ID        VARCHAR(20)   NOT NULL,
    INVOICE_NUMBER    VARCHAR(30)   NOT NULL,
    SUPPLIER          VARCHAR(200)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    COST_CENTER_ID    VARCHAR(10),
    INVOICE_DATE      DATE          NOT NULL,
    DUE_DATE          DATE,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    CURRENCY          VARCHAR(3)    DEFAULT 'USD',
    STATUS            VARCHAR(20)   NOT NULL,
    PAYMENT_DATE      DATE,
    PO_NUMBER         VARCHAR(20),
    DESCRIPTION       VARCHAR(500),
    SUBMITTED_BY      VARCHAR(100),
    APPROVED_BY       VARCHAR(100),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Normal invoices (~4,800)
INSERT INTO RAW_AP_INVOICES
WITH
date_seq AS (
    SELECT DATEADD('day', SEQ4(), '2024-07-01'::DATE) AS dt
    FROM TABLE(GENERATOR(ROWCOUNT => 730))
    WHERE DAYOFWEEK(DATEADD('day', SEQ4(), '2024-07-01'::DATE)) NOT IN (0, 6)
),
suppliers AS (
    SELECT column1 AS supplier_name, column2 AS bc
    FROM VALUES
        ('Bosch Automotive', 'BC 011'),('Continental AG', 'BC 011'),
        ('BorgWarner Inc', 'BC 018'),('Eaton Corporation', 'BC 018'),
        ('Delphi Technologies', 'BC 011'),('Mahle GmbH', 'BC 032'),
        ('Denso Corporation', 'BC 018'),('ZF Friedrichshafen', 'BC 025'),
        ('Honeywell Turbo', 'BC 018'),('Fleetguard', 'BC 011'),
        ('AWS', 'BC 050'),('Microsoft Azure', 'BC 050'),
        ('Salesforce', 'BC 050'),('SAP SE', 'BC 050'),
        ('Deloitte Consulting', 'BC 050'),('Accenture', 'BC 050'),
        ('Parker Hannifin', 'BC 032'),('Cummins Turbo Tech', 'BC 018'),
        ('Houghton International', 'BC 011'),('Castrol Industrial', 'BC 032')
),
numbered AS (
    SELECT supplier_name, bc, ROW_NUMBER() OVER (ORDER BY supplier_name) AS rn
    FROM suppliers
),
base AS (
    SELECT
        d.dt,
        ROW_NUMBER() OVER (ORDER BY d.dt, RANDOM()) AS seq_num
    FROM date_seq d
    WHERE UNIFORM(1, 100, RANDOM()) <= 10  -- ~10% of business days
)
SELECT
    'INV-' || LPAD(b.seq_num::VARCHAR, 6, '0') AS invoice_id,
    'WD-' || DATE_PART('year', b.dt) || '-' || LPAD(b.seq_num::VARCHAR, 5, '0') AS invoice_number,
    s.supplier_name,
    s.bc AS business_code,
    (SELECT COST_CENTER_ID FROM RAW_COST_CENTERS WHERE BUSINESS_CODE = s.bc ORDER BY RANDOM() LIMIT 1) AS cost_center_id,
    b.dt AS invoice_date,
    DATEADD('day', 30, b.dt) AS due_date,
    ROUND(UNIFORM(500, 250000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2) AS amount,
    'USD' AS currency,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'Pending'
        WHEN 2 THEN 'Pending'
        ELSE 'Paid'
    END AS status,
    CASE WHEN UNIFORM(1, 10, RANDOM()) > 2
         THEN DATEADD('day', UNIFORM(5, 45, RANDOM()), b.dt)
         ELSE NULL
    END AS payment_date,
    'PO-' || LPAD(UNIFORM(10000, 99999, RANDOM())::VARCHAR, 5, '0') AS po_number,
    CASE UNIFORM(1, 6, RANDOM())
        WHEN 1 THEN 'Parts and materials'
        WHEN 2 THEN 'Service contract'
        WHEN 3 THEN 'Consulting engagement'
        WHEN 4 THEN 'Software subscription'
        WHEN 5 THEN 'Equipment lease'
        WHEN 6 THEN 'Maintenance agreement'
    END AS description,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'j.morrison' WHEN 2 THEN 's.chen' WHEN 3 THEN 'r.kim'
        WHEN 4 THEN 'l.wang' WHEN 5 THEN 'a.foster'
    END AS submitted_by,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'finance_approver_1' WHEN 2 THEN 'finance_approver_2'
        WHEN 3 THEN 'director_approval' WHEN 4 THEN 'vp_approval'
    END AS approved_by,
    CURRENT_TIMESTAMP() AS loaded_at
FROM base b
JOIN numbered s ON MOD(b.seq_num, (SELECT COUNT(*) FROM numbered)) + 1 = s.rn;

-- Seed DUPLICATE invoices for anomaly detection (~100 duplicates)
INSERT INTO RAW_AP_INVOICES
SELECT
    'INV-D' || LPAD(ROW_NUMBER() OVER (ORDER BY INVOICE_ID)::VARCHAR, 5, '0'),
    INVOICE_NUMBER,          -- same invoice number = duplicate
    SUPPLIER,
    BUSINESS_CODE,
    COST_CENTER_ID,
    DATEADD('day', UNIFORM(1, 3, RANDOM()), INVOICE_DATE),  -- slightly different date
    DUE_DATE,
    AMOUNT,                  -- same amount
    CURRENCY,
    STATUS,
    PAYMENT_DATE,
    PO_NUMBER,
    DESCRIPTION,
    SUBMITTED_BY,
    APPROVED_BY,
    CURRENT_TIMESTAMP()
FROM RAW_AP_INVOICES
WHERE STATUS = 'Paid'
ORDER BY RANDOM()
LIMIT 100;

-- Seed SUSPICIOUS entries: round-number, weekend, unusually large
INSERT INTO RAW_AP_INVOICES
SELECT
    'INV-S' || LPAD(ROW_NUMBER() OVER (ORDER BY RANDOM())::VARCHAR, 5, '0'),
    'SUSP-' || LPAD(ROW_NUMBER() OVER (ORDER BY RANDOM())::VARCHAR, 5, '0'),
    SUPPLIER,
    BUSINESS_CODE,
    COST_CENTER_ID,
    -- weekend dates
    CASE WHEN UNIFORM(1, 2, RANDOM()) = 1
         THEN NEXT_DAY(INVOICE_DATE, 'SA')
         ELSE NEXT_DAY(INVOICE_DATE, 'SU')
    END,
    DUE_DATE,
    -- round-number large amounts
    ROUND(UNIFORM(100, 500, RANDOM()) * 1000, 0),
    CURRENCY,
    'Paid',
    PAYMENT_DATE,
    NULL,  -- no PO
    'Manual adjustment - period end',
    'unknown_user',
    'self_approved',
    CURRENT_TIMESTAMP()
FROM RAW_AP_INVOICES
ORDER BY RANDOM()
LIMIT 50;


-- ────────────────────────────────────────────────────────────
-- 5. RAW_REVENUE  (~200 rows)
--    Maps to: Customer Revenue Dashboard (aggregate level)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_REVENUE (
    REVENUE_CATEGORY  VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_REVENUE
WITH rev_cats AS (
    SELECT column1 AS rev_cat, column2 AS bc, column3 AS monthly_base
    FROM VALUES
        ('Product Revenue',     'BC 011', 45000000),
        ('Product Revenue',     'BC 018', 28000000),
        ('Product Revenue',     'BC 032', 22000000),
        ('Service Revenue',     'BC 011',  8000000),
        ('Service Revenue',     'BC 025', 12000000),
        ('Aftermarket Revenue', 'BC 011', 15000000),
        ('Aftermarket Revenue', 'BC 025',  9000000),
        ('Power Generation',    'BC 032', 18000000),
        ('New Power Revenue',   'BC 040',  3000000)
),
months AS (
    SELECT column1 AS fy, column2 AS m
    FROM VALUES
        ('FY2025',1),('FY2025',2),('FY2025',3),('FY2025',4),('FY2025',5),('FY2025',6),
        ('FY2025',7),('FY2025',8),('FY2025',9),('FY2025',10),('FY2025',11),('FY2025',12),
        ('FY2026',1),('FY2026',2),('FY2026',3),('FY2026',4),('FY2026',5),('FY2026',6),
        ('FY2026',7),('FY2026',8),('FY2026',9),('FY2026',10),('FY2026',11),('FY2026',12)
)
SELECT
    r.rev_cat,
    r.bc,
    m.fy,
    m.m,
    ROUND(r.monthly_base * (0.90 + UNIFORM(0, 20, RANDOM()) / 100.0)
          * CASE WHEN m.m IN (3,6,9,12) THEN 1.12 ELSE 1.0 END
          * CASE WHEN m.fy = 'FY2026' THEN 1.06 ELSE 1.0 END, 2),
    CURRENT_TIMESTAMP()
FROM rev_cats r
CROSS JOIN months m;


-- ────────────────────────────────────────────────────────────
-- 6. RAW_CUSTOMER_REVENUE  (~2K rows)
--    Maps to: Customer Revenue Dashboard (detail level)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_CUSTOMER_REVENUE (
    CUSTOMER_NAME     VARCHAR(200)  NOT NULL,
    CUSTOMER_ID       VARCHAR(20)   NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    REVENUE_CATEGORY  VARCHAR(100)  NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    PAYMENT_DATE      DATE,
    PAYMENT_STATUS    VARCHAR(20),
    DAYS_TO_PAY       INT,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_CUSTOMER_REVENUE
WITH customers AS (
    SELECT column1 AS cust_name, column2 AS cust_id, column3 AS bc, column4 AS rev_cat, column5 AS annual_base
    FROM VALUES
        ('PACCAR Inc',           'CUST-001', 'BC 011', 'Product Revenue',     5400000),
        ('Daimler Trucks NA',    'CUST-002', 'BC 011', 'Product Revenue',     7200000),
        ('Navistar International','CUST-003', 'BC 011', 'Product Revenue',     4800000),
        ('Volvo Group',          'CUST-004', 'BC 011', 'Product Revenue',     6000000),
        ('Tata Motors',          'CUST-005', 'BC 011', 'Product Revenue',     3600000),
        ('John Deere',           'CUST-006', 'BC 032', 'Power Generation',    4200000),
        ('Caterpillar',          'CUST-007', 'BC 032', 'Power Generation',    5400000),
        ('Komatsu',              'CUST-008', 'BC 032', 'Product Revenue',     3000000),
        ('Stellantis',           'CUST-009', 'BC 018', 'Product Revenue',     4800000),
        ('Toyota Motor',         'CUST-010', 'BC 018', 'Product Revenue',     3600000),
        ('BMW Group',            'CUST-011', 'BC 018', 'Product Revenue',     2400000),
        ('Rush Enterprises',     'CUST-012', 'BC 025', 'Service Revenue',     3600000),
        ('FleetPride',           'CUST-013', 'BC 025', 'Aftermarket Revenue', 2400000),
        ('Penske Truck Leasing', 'CUST-014', 'BC 025', 'Service Revenue',     4200000),
        ('Ryder System',         'CUST-015', 'BC 011', 'Aftermarket Revenue', 3000000),
        ('MAN Energy Solutions', 'CUST-016', 'BC 032', 'Power Generation',    3600000),
        ('Wartsila',             'CUST-017', 'BC 032', 'Power Generation',    2400000),
        ('Hyliion',              'CUST-018', 'BC 040', 'New Power Revenue',   1200000),
        ('Nikola Corporation',   'CUST-019', 'BC 040', 'New Power Revenue',    800000),
        ('Lion Electric',        'CUST-020', 'BC 040', 'New Power Revenue',    600000)
),
months AS (
    SELECT column1 AS fy, column2 AS m
    FROM VALUES
        ('FY2025',1),('FY2025',2),('FY2025',3),('FY2025',4),('FY2025',5),('FY2025',6),
        ('FY2025',7),('FY2025',8),('FY2025',9),('FY2025',10),('FY2025',11),('FY2025',12),
        ('FY2026',1),('FY2026',2),('FY2026',3),('FY2026',4),('FY2026',5),('FY2026',6),
        ('FY2026',7),('FY2026',8),('FY2026',9),('FY2026',10),('FY2026',11),('FY2026',12)
)
SELECT
    c.cust_name,
    c.cust_id,
    c.bc,
    c.rev_cat,
    m.fy,
    m.m,
    ROUND((c.annual_base / 12.0)
          * (0.85 + UNIFORM(0, 30, RANDOM()) / 100.0)
          * CASE WHEN m.m IN (3,6,9,12) THEN 1.15 ELSE 1.0 END
          * CASE WHEN m.fy = 'FY2026' THEN 1.06 ELSE 1.0 END, 2),
    DATEADD('day', UNIFORM(15, 60, RANDOM()),
            DATE_FROM_PARTS(CASE WHEN m.fy = 'FY2025' THEN 2025 ELSE 2026 END, m.m, 1)),
    CASE WHEN UNIFORM(1, 20, RANDOM()) = 1 THEN 'Overdue' ELSE 'Paid' END,
    UNIFORM(15, 75, RANDOM()),
    CURRENT_TIMESTAMP()
FROM customers c
CROSS JOIN months m;


-- ────────────────────────────────────────────────────────────
-- 7. RAW_HEADCOUNT  (~350 rows)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_HEADCOUNT (
    ORGANIZATION  VARCHAR(100)  NOT NULL,
    BUSINESS_CODE VARCHAR(10)   NOT NULL,
    FISCAL_YEAR   VARCHAR(6)    NOT NULL,
    MONTH         INT           NOT NULL,
    HC            INT           NOT NULL,
    LOADED_AT     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_HEADCOUNT
WITH orgs AS (
    SELECT DISTINCT ORGANIZATION, BUSINESS_CODE FROM RAW_COST_CENTERS
),
months AS (
    SELECT column1 AS fy, column2 AS m
    FROM VALUES
        ('FY2025',1),('FY2025',2),('FY2025',3),('FY2025',4),('FY2025',5),('FY2025',6),
        ('FY2025',7),('FY2025',8),('FY2025',9),('FY2025',10),('FY2025',11),('FY2025',12),
        ('FY2026',1),('FY2026',2),('FY2026',3),('FY2026',4),('FY2026',5),('FY2026',6),
        ('FY2026',7),('FY2026',8),('FY2026',9),('FY2026',10),('FY2026',11),('FY2026',12)
)
SELECT
    o.ORGANIZATION,
    o.BUSINESS_CODE,
    m.fy,
    m.m,
    CASE o.ORGANIZATION
        WHEN 'Engine Business' THEN 12000 + UNIFORM(-200, 200, RANDOM())
        WHEN 'Components'      THEN  8000 + UNIFORM(-150, 150, RANDOM())
        WHEN 'Distribution'    THEN  5500 + UNIFORM(-100, 100, RANDOM())
        WHEN 'Power Systems'   THEN  7000 + UNIFORM(-120, 120, RANDOM())
        WHEN 'New Power'       THEN  2500 + UNIFORM(-50, 50, RANDOM())
        WHEN 'Corporate'       THEN  3000 + UNIFORM(-50, 50, RANDOM())
    END,
    CURRENT_TIMESTAMP()
FROM orgs o
CROSS JOIN months m;


-- ────────────────────────────────────────────────────────────
-- 8. RAW_EXPENSE_FORECAST  (~10K rows)
--    Maps to: Forecast Data for Variance Analysis
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_EXPENSE_FORECAST (
    ORGANIZATION      VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    EXPENSE_CATEGORY  VARCHAR(100)  NOT NULL,
    PLANNING_VERSION  VARCHAR(20)   NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    IS_GAAP_ONLY      BOOLEAN       DEFAULT FALSE,
    SW_SUBCATEGORY    VARCHAR(100),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_EXPENSE_FORECAST
WITH versions AS (
    SELECT column1 AS ver FROM VALUES ('Plan'),('Q1FC'),('Q2FC'),('Q3FC')
)
SELECT
    e.ORGANIZATION,
    e.BUSINESS_CODE,
    e.EXPENSE_CATEGORY,
    v.ver AS planning_version,
    e.FISCAL_YEAR,
    e.MONTH,
    ROUND(e.AMOUNT *
        CASE v.ver
            WHEN 'Plan'  THEN (0.92 + UNIFORM(0, 16, RANDOM()) / 100.0)
            WHEN 'Q1FC'  THEN (0.95 + UNIFORM(0, 10, RANDOM()) / 100.0)
            WHEN 'Q2FC'  THEN (0.97 + UNIFORM(0, 6, RANDOM()) / 100.0)
            WHEN 'Q3FC'  THEN (0.98 + UNIFORM(0, 4, RANDOM()) / 100.0)
        END, 2) AS amount,
    e.IS_GAAP_ONLY,
    e.SW_SUBCATEGORY,
    CURRENT_TIMESTAMP()
FROM RAW_EXPENSE_REPORT e
CROSS JOIN versions v;


-- ────────────────────────────────────────────────────────────
-- 9. RAW_REVENUE_FORECAST
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_REVENUE_FORECAST (
    REVENUE_CATEGORY  VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    PLANNING_VERSION  VARCHAR(20)   NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    AMOUNT            NUMBER(18,2)  NOT NULL,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_REVENUE_FORECAST
WITH versions AS (
    SELECT column1 AS ver FROM VALUES ('Plan'),('Q1FC'),('Q2FC'),('Q3FC')
)
SELECT
    r.REVENUE_CATEGORY,
    r.BUSINESS_CODE,
    v.ver,
    r.FISCAL_YEAR,
    r.MONTH,
    ROUND(r.AMOUNT *
        CASE v.ver
            WHEN 'Plan'  THEN (0.90 + UNIFORM(0, 20, RANDOM()) / 100.0)
            WHEN 'Q1FC'  THEN (0.93 + UNIFORM(0, 14, RANDOM()) / 100.0)
            WHEN 'Q2FC'  THEN (0.96 + UNIFORM(0, 8, RANDOM()) / 100.0)
            WHEN 'Q3FC'  THEN (0.98 + UNIFORM(0, 4, RANDOM()) / 100.0)
        END, 2),
    CURRENT_TIMESTAMP()
FROM RAW_REVENUE r
CROSS JOIN versions v;


-- ────────────────────────────────────────────────────────────
-- 10. RAW_HEADCOUNT_FORECAST
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE RAW_HEADCOUNT_FORECAST (
    ORGANIZATION      VARCHAR(100)  NOT NULL,
    BUSINESS_CODE     VARCHAR(10)   NOT NULL,
    PLANNING_VERSION  VARCHAR(20)   NOT NULL,
    FISCAL_YEAR       VARCHAR(6)    NOT NULL,
    MONTH             INT           NOT NULL,
    HC                INT           NOT NULL,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_HEADCOUNT_FORECAST
WITH versions AS (
    SELECT column1 AS ver FROM VALUES ('Plan'),('Q1FC'),('Q2FC'),('Q3FC')
)
SELECT
    h.ORGANIZATION,
    h.BUSINESS_CODE,
    v.ver,
    h.FISCAL_YEAR,
    h.MONTH,
    h.HC + CASE v.ver
        WHEN 'Plan'  THEN UNIFORM(-300, 300, RANDOM())
        WHEN 'Q1FC'  THEN UNIFORM(-200, 200, RANDOM())
        WHEN 'Q2FC'  THEN UNIFORM(-100, 100, RANDOM())
        WHEN 'Q3FC'  THEN UNIFORM(-50, 50, RANDOM())
    END,
    CURRENT_TIMESTAMP()
FROM RAW_HEADCOUNT h
CROSS JOIN versions v;
