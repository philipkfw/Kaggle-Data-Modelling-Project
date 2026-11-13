# Kaggle-Data-Modelling-Project
Intended to showcase my data modelling skills with dbt-core in Snowflake!

The project follows a medallion architecture in a single Snowflake database (`KAGGLE_DB`):

| Schema | Purpose |
|---|---|
| `BRONZE` | Raw data, loaded as-is from the source CSVs |
| `SILVER` | Cleaned, typed and conformed models (dbt) |
| `GOLD` | Business-ready marts (dbt) |

## Repository Structure

```
.
├── static_csv_files/          # Source CSVs (Kaggle dataset)
└── snowflake/
    └── 01_setup_bronze.sql    # Warehouse, database, schemas, stage + bronze load
```

---

## Snowflake Setup

### 1. Create a free Snowflake trial account
1. Sign up at [signup.snowflake.com](https://signup.snowflake.com/). The trial lasts 30 days and includes about $400 of credits, with no credit card required.
2. Choose the **Enterprise** edition and any cloud provider/region near you (AWS or Azure are fine).
3. Confirm your email, then create a username and password. New accounts must enrol in **MFA** (typically the Duo Mobile app).
4. You'll land in **Snowsight**, Snowflake's web interface.

### 2. Create the Snowflake objects (Part A)
In Snowsight, go to **Projects → Workspaces** (or **Worksheets**) and create a new SQL file. Paste in **Part A** of [`snowflake/01_setup_bronze.sql`](snowflake/01_setup_bronze.sql) and click **Run All**.

Part A creates:
- **Warehouse** `COMPUTE_WH`: XSMALL, auto-suspends after 60 idle seconds to conserve credits.
- **Database** `KAGGLE_DB`, with schemas `BRONZE`, `SILVER` and `GOLD`.
- **File format** `BRONZE.CSV_FORMAT` and internal **stage** `BRONZE.RAW_CSV_STAGE` (the storage area the CSVs are uploaded into before loading).

All objects are created with the `SYSADMIN` role rather than `ACCOUNTADMIN`.

### 3. Upload the CSVs to the stage
1. In Snowsight, go to **Catalog / Data → Databases → KAGGLE_DB → BRONZE → Stages → RAW_CSV_STAGE**.
2. Click **+ Files** and upload all 6 files from [`static_csv_files/`](static_csv_files/).
3. Run `LIST @RAW_CSV_STAGE;` and confirm all 6 files are listed.

### 4. Load the bronze tables (Part B)
Run **Part B** of the script. It creates the 6 bronze tables, loads each one with `COPY INTO`, and finishes with a row-count check. Expected counts:

| Table | Rows |
|---|---|
| `ACCOUNTS` | 200 |
| `ACCOUNTS_GEO` | 200 |
| `ACCOUNT_LIFECYCLE_EVENTS` | 427 |
| `INVOICES` | 609 |
| `INVOICE_LINE_ITEMS` | 1848 |
| `PAYMENT_TRANSACTIONS` | 435 |

Bronze design notes:
- **Columns match the source CSVs.** Renaming and cleanup belong in silver.
- **Audit columns.** Every table has `_SOURCE_FILE` (the staged file the row came from) and `_LOADED_AT` (load timestamp).
- **Amounts are stored as whole numbers** (e.g. `7632`), as in the source. Whether these are dollars or cents is decided in silver.
- **Re-runnable.** Tables use `CREATE OR REPLACE`, so re-running Part B is a full reload with no duplicate rows.

### 5. Connect VS Code to Snowflake
1. In VS Code, open the Extensions panel (`⇧⌘X`), search for **Snowflake**, and install the official extension published by Snowflake.
2. Click the Snowflake icon in the sidebar and sign in with:
   - **Account identifier**: in Snowsight, click your name (bottom-left) → **Account → View account details**. Format: `ORGNAME-ACCOUNTNAME`.
   - **Username and password**, then approve the Duo MFA push.
3. Open any `.sql` file and press `⌘+Enter` to run the statement under the cursor. Use the sidebar's object browser to explore `KAGGLE_DB.BRONZE`.
4. *Optional:* to avoid an MFA prompt on every connection, set up [key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth). The same key can be reused by dbt later.
