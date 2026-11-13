/* =============================================================================
   01_setup_bronze.sql
   One-time setup: warehouse, database, medallion schemas, and raw CSV load
   into the BRONZE schema.

   Run in two passes:
     PART A  -> creates objects (incl. the stage you upload CSVs into)
     (upload the 6 CSVs to KAGGLE_DB.BRONZE.RAW_CSV_STAGE)
     PART B  -> creates bronze tables and loads them with COPY INTO

   Safe to re-run: tables are CREATE OR REPLACE, so a re-run is a full reload.
============================================================================= */

/* =============================== PART A ================================== */

USE ROLE SYSADMIN;   -- create objects as SYSADMIN, not ACCOUNTADMIN

-- Compute: smallest size, suspends after 60s idle so trial credits last
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS KAGGLE_DB;

CREATE SCHEMA IF NOT EXISTS KAGGLE_DB.BRONZE COMMENT = 'Raw data, as landed from source CSVs';
CREATE SCHEMA IF NOT EXISTS KAGGLE_DB.SILVER COMMENT = 'Cleaned, typed, conformed models';
CREATE SCHEMA IF NOT EXISTS KAGGLE_DB.GOLD   COMMENT = 'Business-ready marts';

USE WAREHOUSE COMPUTE_WH;
USE SCHEMA KAGGLE_DB.BRONZE;

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE
  COMPRESSION = AUTO;          -- handles both .csv and .csv.gz

CREATE STAGE IF NOT EXISTS RAW_CSV_STAGE
  FILE_FORMAT = CSV_FORMAT
  COMMENT = 'Internal stage for static Kaggle CSV uploads';

-- >>> STOP HERE. Upload the 6 CSV files to KAGGLE_DB.BRONZE.RAW_CSV_STAGE <<<
-- Then confirm they're there:
LIST @RAW_CSV_STAGE;


/* =============================== PART B ================================== */
/* Each table keeps the source columns plus two load-audit columns:
     _SOURCE_FILE  - the staged file the row came from
     _LOADED_AT    - when the row was loaded
   Types follow the source data; silver will rename and conform them. */

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA KAGGLE_DB.BRONZE;

-- ---------- ACCOUNTS ----------
CREATE OR REPLACE TABLE ACCOUNTS (
  ID                VARCHAR,
  SIGN_UP_TIME      TIMESTAMP_NTZ,
  SIGN_UP_PLATFORM  VARCHAR,
  _SOURCE_FILE      VARCHAR,
  _LOADED_AT        TIMESTAMP_LTZ
);
COPY INTO ACCOUNTS
FROM (SELECT $1, $2, $3, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Accounts[.]csv.*'
ON_ERROR = ABORT_STATEMENT;

-- ---------- ACCOUNTS_GEO ----------
CREATE OR REPLACE TABLE ACCOUNTS_GEO (
  ACCOUNT_ID    VARCHAR,
  COUNTRY       VARCHAR,
  CITY          VARCHAR,
  REGION        VARCHAR,
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);
COPY INTO ACCOUNTS_GEO
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Accounts_Geo[.]csv.*'
ON_ERROR = ABORT_STATEMENT;

-- ---------- ACCOUNT_LIFECYCLE_EVENTS ----------
CREATE OR REPLACE TABLE ACCOUNT_LIFECYCLE_EVENTS (
  ACCOUNT_ID       VARCHAR,
  EVENT_TIME       TIMESTAMP_NTZ,
  LIFECYCLE_STATE  VARCHAR,
  _SOURCE_FILE     VARCHAR,
  _LOADED_AT       TIMESTAMP_LTZ
);
COPY INTO ACCOUNT_LIFECYCLE_EVENTS
FROM (SELECT $1, $2, $3, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Account_Lifecycle_Events[.]csv.*'
ON_ERROR = ABORT_STATEMENT;

-- ---------- INVOICES ----------
CREATE OR REPLACE TABLE INVOICES (
  ACCOUNT_ID            VARCHAR,
  INVOICE_ID            VARCHAR,
  INVOICE_CREATED_TIME  TIMESTAMP_NTZ,
  INVOICE_SENT_TIME     TIMESTAMP_NTZ,
  AMOUNT                NUMBER(38,0),
  CURRENCY              VARCHAR,
  _SOURCE_FILE          VARCHAR,
  _LOADED_AT            TIMESTAMP_LTZ
);
COPY INTO INVOICES
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Invoices[.]csv.*'
ON_ERROR = ABORT_STATEMENT;

-- ---------- INVOICE_LINE_ITEMS ----------
CREATE OR REPLACE TABLE INVOICE_LINE_ITEMS (
  INVOICE_ID    VARCHAR,
  ID            VARCHAR,
  SERVICE_TYPE  VARCHAR,
  AMOUNT        NUMBER(38,0),
  _SOURCE_FILE  VARCHAR,
  _LOADED_AT    TIMESTAMP_LTZ
);
COPY INTO INVOICE_LINE_ITEMS
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Invoice_Line_Items[.]csv.*'
ON_ERROR = ABORT_STATEMENT;

-- ---------- PAYMENT_TRANSACTIONS ----------
CREATE OR REPLACE TABLE PAYMENT_TRANSACTIONS (
  ACCOUNT_ID        VARCHAR,
  INVOICE_ID        VARCHAR,
  TRANSACTION_ID    VARCHAR,
  TRANSACTION_TIME  TIMESTAMP_NTZ,
  PAYMENT_METHOD    VARCHAR,
  AMOUNT            NUMBER(38,0),
  CURRENCY          VARCHAR,
  _SOURCE_FILE      VARCHAR,
  _LOADED_AT        TIMESTAMP_LTZ
);
COPY INTO PAYMENT_TRANSACTIONS
FROM (SELECT $1, $2, $3, $4, $5, $6, $7, METADATA$FILENAME, CURRENT_TIMESTAMP() FROM @RAW_CSV_STAGE)
PATTERN = '.*Payment_Transactions[.]csv.*'
ON_ERROR = ABORT_STATEMENT;


/* ============================ VERIFY ===================================== */
-- Expected row counts (source line count minus header):
--   ACCOUNTS 200 | ACCOUNTS_GEO 200 | ACCOUNT_LIFECYCLE_EVENTS 427
--   INVOICES 609 | INVOICE_LINE_ITEMS 1848 | PAYMENT_TRANSACTIONS 435
SELECT 'ACCOUNTS' AS table_name, COUNT(*) AS row_count FROM ACCOUNTS
UNION ALL SELECT 'ACCOUNTS_GEO',             COUNT(*) FROM ACCOUNTS_GEO
UNION ALL SELECT 'ACCOUNT_LIFECYCLE_EVENTS', COUNT(*) FROM ACCOUNT_LIFECYCLE_EVENTS
UNION ALL SELECT 'INVOICES',                 COUNT(*) FROM INVOICES
UNION ALL SELECT 'INVOICE_LINE_ITEMS',       COUNT(*) FROM INVOICE_LINE_ITEMS
UNION ALL SELECT 'PAYMENT_TRANSACTIONS',     COUNT(*) FROM PAYMENT_TRANSACTIONS
ORDER BY 1;