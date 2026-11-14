# Data Quality, Assumptions and Limitations

## 1. How issues are identified

| Stage | Mechanism |
|---|---|
| Discovery | Source profiling queries, saved in [`analyses/source_profiling.sql`](../analyses/source_profiling.sql) and compiled with `dbt compile` |
| Every build | 176 dbt tests: 162 generic (`unique`, `not_null`, `relationships`, `accepted_values`, `dbt_utils` range / combination / expression tests) + 14 singular tests in `tests/` |
| Known anomalies | Warn-severity tests report counts on every run without failing the build |

**Principle: records are flagged, never silently removed.** Anomalies stay in all metrics and carry an `is_*` flag, so totals always reconcile back to the source.

### Singular tests
| Folder | Test | Purpose |
|---|---|---|
| `financial/` | `assert_invoice_amount_matches_line_items` | Invoice amount = Σ line items |
| | `assert_payment_account_matches_invoice_account` | The redundant `account_id` paths agree |
| | `assert_currency_matches_account_country` | Currency is the account's local currency |
| | `assert_fx_rates_complete` | A rate exists for every date × currency |
| `reporting/` | `assert_gpv_reconciles_to_source` | GPV: source → fact → marts |
| | `assert_invoice_volume_reconciles_to_source` | Invoice count and amount: source → fact → marts |
| | `assert_lifecycle_counts_reconcile` | Stage counts match the snapshot, sign-ups and current stages |
| | `assert_monthly_mart_reconciles_to_daily` | Monthly mart = daily marts |
| | `assert_segmentation_complete` | No `'Unknown'` country, region, city or platform |
| `lifecycle/` | `assert_no_overlapping_lifecycle_intervals` | No account is in two states at once |
| | `assert_one_current_lifecycle_state_per_account` | Exactly one open interval per account |
| | `assert_valid_lifecycle_transitions` *(warn)* | Flags paths outside trial → subscribed → churned |
| `data_quality/` | `warn_post_churn_activity` *(warn)* | Reports post-churn invoices and payments |
| | `warn_stale_trials` *(warn)* | Reports trials with no end event |

**Latest build:** all tests pass. The 2 expected warnings are 61 stale trials and 27 post-churn records.

## 2. Source data quality findings

**Structurally, the data is clean:**
- No nulls, blanks or duplicate rows.
- No duplicate primary keys and no orphaned foreign keys.
- Every account has exactly one geography row.
- Every invoice reconciles exactly to its line items (609 / 609).
- Every paid invoice has exactly one full payment.
- No zero or negative amounts, and no out-of-order timestamps.

The issues are semantic:

| # | Finding | Impact | Handling |
|---|---|---|---|
| DQ1 | **16 invoices and 11 payments are dated after the account churned** (10 accounts, up to 34 days after) | Activity attributed to churned accounts | Kept in all metrics; `is_post_churn_activity` flag; warn test |
| DQ2 | **61 trial-only accounts have no trial-end event.** No trial ever converts after day 89, yet some trials date from January 2024 | Trial counts include long-dead trials | Reported as recorded (no invented state); `is_stale_trial` flag (> 90 days); warn test |
| DQ3 | **174 invoices (28.6%) have no payment;** there's no invoice status | Outstanding vs. void can't be told apart | Counted in Invoice Volume; `is_paid` flag |
| DQ4 | **No transaction status:** no refunds, failures or reversals | GPV can't exclude anything | GPV includes all transactions; documented |
| DQ5 | **Source timezone unknown** (`TIMESTAMP_NTZ`) | About 20% of records change reporting day under conversion | Assumed UTC; one configurable variable ([methodology](methodology.md#2-timezone-standardisation-mountain-time)) |
| DQ6 | **Amount units not specified** | Dollars vs. cents | Assumed major units (dollars): 103–9,996 per invoice is plausible for field-service jobs |
| DQ7 | **No lifecycle state between sign-up and trial** (1–30 days) | Accounts missing from stage counts | Derived `pre_trial` stage, outside the three required counts |
| DQ8 | **Region isn't hierarchical:** 18 of 20 cities span two regions, and Leeds sits in two UK regions; country naming is mixed (`UK` vs `United States`) | No strict country → region → city drill path | Region treated as an independent attribute; ISO `country_code` added; source values kept |
| DQ9 | **Lifecycle data runs to 2025-08-12, but financial data ends 2025-06-13** | Ambiguous "as-of" date | `reporting_end_date = 2025-08-12` (the latest timestamp in any source) |
| DQ10 | **Synthetic signals:** each account shares one minutes:seconds value across all its timestamps; lags are uniform (sent 1–48h after creation, paid 1–72h after sending) | Patterns are unrealistically clean | Documented only |

## 3. Business assumptions (approved before implementation)

| # | Assumption |
|---|---|
| A1 | Source timestamps are UTC; reporting is in `America/Denver` |
| A2 | FX rates come from Federal Reserve H.10 via FRED, stored as a seed |
| A3 | GPV includes all payment methods, with an electronic/offline split provided |
| A4 | The sign-up → trial gap is a derived `pre_trial` stage |
| A5 | Stale trials are reported as recorded and flagged, not expired |
| A6 | Post-churn activity is included in metrics and flagged |
| A7 | Amounts are in major currency units |
| A8 | The reporting end date is 2025-08-12 |
| A9 | Invoices convert at the created date; payments at the transaction date |
| A10 | Unpaid invoices count toward Invoice Volume |
| A11 | Source country names are kept, with an ISO code added |
| A13 | Dev (`DEV_*`) and prod (`SILVER` / `GOLD`) schemas are isolated |

## 4. Limitations

- **Segmentation reflects current attributes only.** Geography and platform have no history, so a moved account is segmented by its latest location.
- **FX rates are indicative.** H.10 noon rates aren't processor settlement rates.
- **The data is a static snapshot.** There are no incremental loads, source freshness checks or late-arriving data handling; at this volume none are needed.
- **Trial expiry isn't modelled.** Without an expiry event, the trial stock overstates live trials (see DQ2). Filter on `is_stale_trial` for an adjusted view.
- **The timezone assumption is unverified.** If the source is local time, the city → IANA mapping described in the methodology is needed.
