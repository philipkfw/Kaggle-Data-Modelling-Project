# Metric Definitions

Every metric has exactly one authoritative model. The marts pre-aggregate these definitions, so BI tools never re-implement business logic.

**Segmentation:** every metric can be split by `country`, `country_code`, `region`, `city` and `sign_up_platform`, using each account's current attributes from `dim_accounts`. These attributes are static in the source; there is no history.

---

## Financial metrics

| Metric | Definition | Authoritative model | Date basis |
|---|---|---|---|
| **Gross Payment Volume (GPV)** | `SUM(amount_usd)` over all payment transactions | `fct_payment_transactions` | Transaction date (MT) |
| GPV – electronic | GPV where `payment_channel = 'electronic'` (Credit Card, ACH, Paypal) | `fct_payment_transactions` | Transaction date (MT) |
| GPV – offline | GPV where `payment_channel = 'offline'` (Cash, Cheque) | `fct_payment_transactions` | Transaction date (MT) |
| Payment count | `COUNT(transaction_id)` | `fct_payment_transactions` | Transaction date (MT) |
| **Invoice Volume** | `COUNT(DISTINCT invoice_id)` | `fct_invoices` | Invoice created date (MT) |
| **Invoice Dollar Volume** | `SUM(invoice_amount_usd)` | `fct_invoices` | Invoice created date (MT) |

**Notes:**
- **GPV includes every payment method,** per the project's metric definition. In payments businesses, GPV often means only volume processed through the platform. That would exclude manually recorded cash and cheques, which are **38.4%** of GPV here. The electronic/offline split lets either definition be reported without changing the model.
- **No transactions are excluded.** The source has no status, refund, failure or reversal field, and every amount is positive.
- **Invoice Volume counts every invoice,** paid or not: 174 of 609 have no payment. `fct_invoices.is_paid` allows filtering, but the source has no invoice status, so unpaid can't be split into outstanding vs. void.
- **Invoice count and invoice dollar volume are separate metrics.**

## Lifecycle metrics

| Metric | Type | Definition | Authoritative model |
|---|---|---|---|
| **Trial Accounts** | Stock | Accounts whose end-of-day (MT) stage is `trial` | `fct_account_daily_status` |
| **Subscribed Accounts** | Stock | Accounts whose end-of-day stage is `subscribed` | `fct_account_daily_status` |
| **Churned Accounts** | Stock | Accounts whose end-of-day stage is `churned` (cumulative; churn is terminal) | `fct_account_daily_status` |
| Pre-trial Accounts | Stock | Signed up, no trial event yet | `fct_account_daily_status` |
| Total Accounts | Stock | All accounts signed up by end of day (the sum of the four stages) | `fct_account_daily_status` |
| New Sign-ups | Flow | Accounts that signed up on the date | `dim_accounts` |
| New Trials / Subscriptions / Churns | Flow | Lifecycle events of that type on the date | `fct_account_lifecycle` |

- **Current counts** = the stocks on the reporting end date (2025-08-12): 61 trial, 51 subscribed, 88 churned.
- **Historical counts** = the stocks on any earlier date.

## Rates (computed in the BI tool)

Ratios can't be summed across segments or periods, so they're calculated from additive components.

| Rate | Numerator | Denominator | Source |
|---|---|---|---|
| **Trial → Subscribed conversion** | Accounts with `has_converted_within_window` (subscribed within 90 days of trial start) | Accounts that started a trial in the cohort period (by `trial_started_date_mt`) | `dim_accounts` |
| **Monthly churn rate** | `new_churns` in month M | `subscribed_accounts_eom` of month M−1 | `mart_account_performance` |

- **Conversion cohorts:** group accounts by the month their trial *started*. Only use trials that started on or before 2025-05-14 (90 days before the reporting end date); later trials haven't had the full window to convert. No trial in the data converted after day 89.
- **Churn rate denominator:** the subscribers at the start of the month, i.e. the previous month's closing balance.

---

## Reporting marts

| Mart | Grain | Use it for |
|---|---|---|
| `mart_financial_performance` | reporting date × segment (sparse: only rows with activity) | Daily and weekly GPV and invoice trends |
| `mart_account_lifecycle` | reporting date × segment (dense from each segment's first sign-up) | Daily stage distribution, lifecycle flows |
| `mart_account_performance` | month × segment | Executive monthly view combining all metrics |

### Additivity: the one rule BI users must follow

| Measure type | Columns | Sum across segments? | Sum across dates? |
|---|---|---|---|
| Flows and financials | `gpv_*`, `payment_count`, `invoice_*`, `new_*` | ✅ | ✅ |
| Stocks | `*_accounts`, `*_accounts_eom` | ✅ | ❌ – take the **last date** of the period |

**Example:**
- **Right:** "subscribed accounts in Q3 2024" = subscribed accounts on 2024-09-30, i.e. 53.
- **Wrong:** summing the daily values across July–September gives a meaningless number.

In a BI tool, filter to the period's last date or use the monthly mart's `*_eom` columns (see [bi_connection.md](bi_connection.md)).

## Reconciliation guarantees (tested on every build)
- **GPV:** Bronze source = fact = daily mart = monthly mart, per currency and in USD. Electronic + offline = total.
- **Invoice Volume and Invoice Dollar Volume:** source = fact = daily mart = monthly mart.
- **Stage counts:** they equal the account-day snapshot on every date, equal the accounts signed up by that date, and equal `dim_accounts` current stages on the reporting end date.
- **Monthly mart:** month-end stocks and monthly flows equal the daily mart.
