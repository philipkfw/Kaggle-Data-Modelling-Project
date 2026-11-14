# Methodology

How currency, timezone and lifecycle history are handled, and why.

---

## 1. Currency conversion (historical FX → USD)

### The problem
Invoices and payments are in four currencies: USD, CAD, GBP and AUD. Each account uses exactly one currency, matching its country (US → USD, Canada → CAD, UK → GBP, Australia → AUD; a test enforces this). Converting historical amounts at today's rate would misstate past volume, so each record is converted at the rate in effect on its own date.

### Source: Federal Reserve H.10 via FRED
| Series | Quote | Normalised to "1 unit = X USD" |
|---|---|---|
| `DEXCAUS` | CAD per 1 USD | `1 / value` |
| `DEXUSUK` | USD per 1 GBP | `value` |
| `DEXUSAL` | USD per 1 AUD | `value` |

**Why this source:**
- **Direct pairs:** these are direct USD rates, so there's no cross-rate triangulation and no extra source of error.
- **Public domain:** the data comes from the Federal Reserve Board.
- **Reproducible:** the rates are stored as a version-controlled seed (`seeds/fx_rates_fred_h10.csv`, 1,314 rows, 2023-12-01 → 2025-08-29). Anyone can rebuild the project without a Snowflake Marketplace subscription.

**Alternatives considered:**
- **Snowflake Marketplace (Snowflake Public Data FX).** Free and Snowflake-native, but it wasn't installed in this account, and anyone rebuilding the project would need to subscribe. If adopted, only `stg_fx_rates` would change.
- **ECB reference rates.** EUR-based, so USD pairs would need triangulating through EUR.

**Published values are stored exactly as published.** US holidays with no published value are left out; no rate is ever imputed or fabricated.

### Rules
1. **Convention:** `exchange_rate` = USD value of 1 unit of `from_currency`. USD has identity rows at 1.0.
2. **Conversion date:**
   - **GPV:** the payment's **transaction date (MT)**.
   - **Invoice Dollar Volume:** the invoice's **created date (MT)**.
3. **Weekends and holidays:** use the most recent rate published **on or before** the date. This is done once in `int_fx_rates_daily` with an `ASOF JOIN`; no future rate is ever applied. The largest carry-forward in the data is 3 days.
4. **Calculation:** `amount_usd = original_amount × exchange_rate`, stored unrounded (`NUMBER(38,6)`) so totals don't drift. Round only for display.
5. **Audit trail:** every fact carries the original amount, original currency, `exchange_rate`, `fx_rate_effective_date`, `fx_rate_source` and the USD amount. Original values are never overwritten.

### Tests
- **Missing or invalid rates:** `amount_usd` and `exchange_rate` are not null; rate is greater than 0.
- **Duplicates:** (`rate_date`, `from_currency`) is unique.
- **Unsupported currencies:** `accepted_values` on currency codes.
- **Coverage:** every currency has a rate for every date in the window (`assert_fx_rates_complete`).
- **Staleness:** `days_since_published` ≤ 4 (`max_fx_staleness_days`).

### Limitation
H.10 rates are New York noon buying rates, an indicative mid-market rate. They aren't the rate a payment processor actually charged. If processor settlement rates are available, swap the seed for them: `stg_fx_rates` keeps the same output contract, so nothing downstream changes.

---

## 2. Timezone standardisation (Mountain Time)

### Source assumption: UTC
The source timestamps are `TIMESTAMP_NTZ` and carry no offset or zone. The data can't prove which zone they're in:
- **No local-time pattern:** activity is spread evenly across all 24 hours in every country. If timestamps were each account's local time, activity would cluster in business hours.
- **No single offset either:** each country's activity doesn't peak at a different UTC hour, as it would under a clean UTC pattern. The data appears to be synthetic.

**The source is assumed to be UTC**, which is the standard for platform-generated event logs. The assumption is a single project variable (`source_timezone: 'UTC'`), so changing it is a one-line change.

**Why it matters:** converting to Mountain Time moves about **20% of records to a different reporting day** (130 of 609 invoices, 115 of 435 payments) and **15 records to a different month**.

### Target: `America/Denver`
Mountain Time is the business's reporting timezone (a project requirement). Reporting in one zone gives every country the same definition of a day and a month.

### Method
- **One macro:** `to_mountain_time(col)` = `CONVERT_TIMEZONE(var('source_timezone'), var('reporting_timezone'), col)`.
  - The 3-argument form is **independent of the Snowflake session timezone** (which is `America/Los_Angeles` in this account).
  - It uses IANA rules, so MST (UTC−7) and MDT (UTC−6) are applied automatically. Verified: 152 payments shifted by −7h and 283 by −6h. No offsets are hardcoded.
- **Applied once, in staging,** to sign-up, lifecycle event, invoice created, invoice sent and payment timestamps.
- **Both values kept:** silver keeps `*_at_utc` (the original) next to `*_at_mt`, for traceability.
- **All reporting dates** (`*_date_mt`) come only from Mountain Time timestamps.
- **Point-in-time comparisons use UTC.** "Which lifecycle stage was the account in when this invoice was created?" is answered in UTC, because Mountain Time repeats an hour when daylight saving ends and so isn't strictly ordered. Day boundaries for reporting use Mountain Time.

### Alternative if the assumption is wrong
If the source turns out to be each account's local time, map each city to its IANA zone (20 cities, e.g. Calgary → `America/Edmonton`, Adelaide → `Australia/Adelaide`) and convert local → Denver in staging. Only the macro input changes.

---

## 3. Historical lifecycle tracking

### Approach: effective-dated intervals + a daily snapshot fact
| Option considered | Decision |
|---|---|
| 2 – Effective-dated intervals (`valid_from`, `valid_to`, `is_current`) | **Core model:** `fct_account_lifecycle`. A compact, exact history that's never overwritten. |
| 1 – Daily snapshot via date spine | **Derived from the intervals:** `fct_account_daily_status`. One row per account per day makes historical counts a simple filter in Tableau. ~79k rows. |
| 3 – dbt snapshots | **Not used.** Snapshots record changes to a *mutable* table across repeated runs. Our source is already an append-only event history, and the CSVs are static, so a snapshot would capture nothing. |

### How state is derived
1. **Sequence** each account's events by time, with a deterministic tie-break by state rank (trial < subscribed < churned). No two events share a timestamp today; the tie-break is a safeguard.
2. **Build intervals:** each event opens an interval `[event_time, next_event_time)`. The last one is open (`valid_to IS NULL`, `is_current = TRUE`).
3. **Snapshot each day:** for every account and calendar date from sign-up to the reporting end date, the **end-of-day (MT) stage** is the latest event before midnight (an `ASOF JOIN`).
4. **Before the first event,** an account is in the derived `pre_trial` stage. It always signs up 1–30 days before its trial event.

### Definitions
- **Stage counts are point-in-time stocks.** `subscribed_accounts` on date D is the number of accounts whose stage at the end of D (MT) is subscribed. **They are not cumulative event counts.**
- **No double counting:** each account has exactly one stage per day, so the stages add up to the total number of signed-up accounts. This is enforced by tests.
- **Churned only grows:** churn is terminal, so the churned stock accumulates over time.
- **Flows are separate measures:** `new_trials`, `new_subscriptions` and `new_churns` count events on a date and are never mixed with stocks.
- **Current state is separate from history:** `dim_accounts.current_lifecycle_stage` holds only the latest state. Historical questions must use the lifecycle facts or marts.

### Invalid transitions
Valid paths are (start) → trial → subscribed → churned. Anything else is flagged with `is_valid_transition = FALSE` and surfaced by a warn-level test. None exist in the current data. Records are flagged, never removed, and the point-in-time logic stays correct either way.

### Verified example
| Date | pre_trial | trial | subscribed | churned | total |
|---|---|---|---|---|---|
| 2024-06-30 | 8 | 42 | 36 | 6 | 92 |
| 2024-12-31 | 10 | 78 | 65 | 47 | 200 |
| 2025-08-12 (current) | 0 | 61 | 51 | 88 | 200 |
