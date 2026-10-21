# Payments Ledger Backlog

Sizes: **S** = under 1 hr, **M** = 1 to 3 hrs, **L** = 3+ hrs. Work top to bottom within each epic.

## Epic 1: Foundation

- **PL-1 (S) — Done** Create Rails API app on Postgres with RSpec and FactoryBot. *Done when:* `bundle exec rspec` runs green on an empty suite.
- **PL-2 (S) — Done** Create private GitHub repo, `.gitignore`, and README stub. *Done when:* first commit pushed, no secrets committed.
- **PL-3 (M) — Done** Set up GitHub Actions CI with a Postgres service container. *Done when:* every push runs specs and the badge is green.
- **PL-4 (S) — Done** Switch to `structure.sql` schema format. *Done when:* DB constraints survive `db:schema:load`.
- **PL-5 (M) — Done** Migrations for `accounts`, `transfers`, `ledger_entries` (money as integer cents). *Done when:* tables exist with foreign keys and indexes.
- **PL-6 (M) — Done** Add database CHECK constraints (positive amount, nonzero entry, source differs from destination). *Done when:* specs prove raw SQL inserts of bad data are rejected.
- **PL-7 (M) - Done** Enforce append-only on `ledger_entries` with a Postgres trigger that blocks UPDATE and DELETE. *Done when:* a spec proves updates and deletes raise.
- **PL-8 (M) — Done** `POST /v1/accounts` endpoint. *Done when:* request spec passes, validation errors return clean JSON.
- **PL-9 (M) — Done** Add a system funding account and implement `POST /v1/accounts/:id/deposits` through the shared money-movement service. *Done when:* every deposit creates a balanced debit and credit, rejects non-positive amounts, and cannot mint an unbalanced ledger entry.
- **PL-10 (S) — Done** `GET /v1/accounts/:id/balance` reads the materialized `accounts.balance_cents`. *Done when:* the balance matches `SUM(ledger_entries)` in specs.

## Epic 2: Transfers and idempotency

- **PL-11 (L) - Done** Shared money-movement service for deposits and account-to-account transfers: one transaction locks accounts, updates materialized balances, and writes balanced debit and credit entries. *Done when:* specs assert entries sum to zero, balances match ledger sums, and all writes exist or neither exists.
- **PL-12 (S) - Done** Reject insufficient funds. *Done when:* returns 422 and writes nothing.
- **PL-13 (S)** Reject invalid transfers (same account, unknown account, bad amount, currency mismatch). *Done when:* each case has a spec.
- **PL-14 (M)** `POST /v1/transfers` endpoint with consistent error format. *Done when:* happy path and all error paths covered by request specs.
- **PL-15 (M)** `idempotency_keys` table with unique index, storing request fingerprint and response. *Done when:* migration and model specs pass.
- **PL-16 (L)** Idempotency middleware or concern with an atomic claim-and-execute flow. *Done when:* concurrent first requests with the same key produce one idempotency record and one transfer, retries wait for or return the stored response, a changed payload with the same key errors (422 or 409), a missing key on transfers is rejected, and an interrupted request does not leave an unrecoverable in-progress record.
- **PL-17 (S)** Rollback test: force a failure between the two entry writes. *Done when:* spec proves no partial transfer remains.

## Epic 3: Concurrency (the key part)

- **PL-18 (L)** Write a failing concurrency test that reproduces the overdraft race (threads, real DB connections, no transactional fixtures). *Done when:* the test reliably shows an overdraft before the fix.
- **PL-19 (M)** Fix the overdraft race with row locks (`SELECT ... FOR UPDATE`) inside the money-movement transaction. *Done when:* the PL-18 test passes and the materialized balance remains equal to the ledger sum.
- **PL-20 (M)** Lock all affected accounts in a consistent order (lowest ID first). *Done when:* simultaneous A-to-B and B-to-A transfers do not deadlock, lose updates, or violate the zero-sum invariant.
- **PL-21 (M)** Retry only transient serialization failures, deadlocks, and transient database connection failures with bounded attempts and backoff. *Done when:* specs cover successful retry and exhausted retries, and prove validation errors and insufficient-funds errors are never retried.
- **PL-22 (M)** Test: 100 concurrent withdrawals never overdraw the account. *Done when:* final balance is never negative, successful withdrawal amounts equal total debited, and `balance_cents` equals the account's ledger sum.
- **PL-23 (M)** Test: concurrent requests with the same idempotency key create exactly one transfer. *Done when:* exactly one transfer row, one idempotency record, and one stored response exist.
- **PL-23A (M)** Test: concurrent bidirectional transfers between the same two accounts. *Done when:* A-to-B and B-to-A requests complete without deadlock, final materialized balances match ledger sums, and every committed transfer has balanced entries.
- **PL-24 (M)** Write up "why row locks over serializable isolation" in `docs/decisions.md`. *Done when:* covers tradeoffs, contention, and failure modes in your own words.

## Epic 4: Reconciliation and audit

- **PL-25 (M)** Reversal flow: a transfer reversal creates new offsetting entries and never edits old ones. *Done when:* reversing twice is rejected, original entries are untouched.
- **PL-26 (L)** Reconciliation job that recomputes every materialized balance from entries and records drift. *Done when:* a spec corrupts `balance_cents` and the job records `account_id`, stored balance, ledger balance, difference, check time, and drift status without silently repairing the value.
- **PL-27 (M)** Background job runner using ActiveJob with Solid Queue or another Rails-native runner. *Done when:* reconciliation runs on a local schedule without Redis.
- **PL-28 (M)** API key authentication. *Done when:* requests without a valid key get 401, keys are stored hashed.
- **PL-29 (M)** Cursor pagination for entries and transfers (`GET /v1/accounts/:id/ledger-entries`). *Done when:* stable ordering, no duplicates across pages.
- **PL-30 (M)** Audit log recording money-moving actions. *Done when:* every deposit, transfer, and reversal produces an audit row containing actor/API-key identifier, action, resource type and ID, request ID, amount and currency where applicable, result/status, and timestamp without storing raw API keys or secrets.

## Epic 5: Ship it

- **PL-31 (M)** Structured JSON logging with request IDs. *Done when:* a transfer can be traced end to end in the logs.
- **PL-32 (M)** Basic metrics (transfer count, failures, latency). *Done when:* exposed on an endpoint or logged in a parseable format.
- **PL-33 (L)** k6 load test for transfer throughput and p95 latency. *Done when:* script is committed, and you have recorded real numbers (these fill your resume brackets).
- **PL-34 (L)** Deploy to Fly.io or Render with managed Postgres. *Done when:* live URL works, migrations run on deploy, secrets are in env vars.
- **PL-35 (M)** Run the k6 test against the deployed app. *Done when:* numbers are recorded with the instance size noted.
- **PL-36 (L)** Final README: architecture diagram, key decisions, tradeoffs, what you'd change at scale, how to run and test. *Done when:* a stranger could clone, run, and understand it in 10 minutes.
- **PL-37 (S)** Add resume bullets using only measured numbers. *Done when:* every bracket in your bullets is filled from PL-22, PL-33, or PL-35.
- **PL-38 (M)** Interview prep doc: a 2-minute pitch plus answers to likely questions (why integer cents, how idempotency works, race condition walkthrough, why row locks, what breaks at 100x scale). *Done when:* you can explain each without notes.

## Optional (only if the core is done)

- **PL-39 (L)** Stretch: webhooks on transfer events, or holds and authorizations.

## Definition of done for the whole project

- CI green, all concurrency tests passing consistently (run them 20 times to check for flakiness)
- Deployed with a live URL
- README and decisions doc complete
- Resume bullets filled with real measured numbers
- Nothing from Scotiabank work used anywhere in the repo

**Tip:** If you fall behind, cut in this order: PL-39 first, then PL-32, then PL-27. Never cut Epic 3. That's the part interviewers will ask about.