# Development

This guide contains technical engineering details for Payments Ledger. The
[README](README.md) provides the project overview and architecture.

## API endpoints

The current API uses the `/v1` namespace and API-key authentication.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/v1/accounts` | Create an account |
| `POST` | `/v1/accounts/:id/deposits` | Deposit funds into an account |
| `GET` | `/v1/accounts/:id/balance` | Read an account balance |
| `GET` | `/v1/accounts/:id/ledger-entries` | List an account's ledger entries |
| `GET` | `/v1/accounts/:id/transfers` | List transfers involving an account |
| `POST` | `/v1/transfers` | Create an account-to-account transfer |
| `POST` | `/v1/transfers/:id/reversal` | Reverse a transfer |
| `GET` | `/up` | Rails health check |

Authenticated `/v1` requests require an API key in the `X-API-Key` header.
Transfer and reversal requests also require an `Idempotency-Key` header.
Reusing an idempotency key with the same payload returns the stored result;
reusing it with a different payload or while the original request is unresolved
returns an error.

Ledger-entry and transfer list requests support cursor pagination. The API
returns records in ascending `(created_at, id)` order and uses a cursor to
prevent duplicates across pages.

## Data model

### Accounts

- `id`
- `currency`
- `balance_cents`
- timestamps

`balance_cents` is an integer maintained transactionally with ledger writes.
The reconciliation job compares it with the account's ledger total and records
drift without silently repairing the value. The service does not use a cache.

### Transfers

- `id`
- source account
- destination account
- amount in cents
- currency
- status
- request metadata and timestamps

A transfer represents a business operation. Its state and response provide the
basis for idempotent retries.

### Ledger entries

- `id`
- account
- transfer
- amount in cents, signed from the account's perspective
- currency
- entry type
- timestamps

Each money movement creates one debit and one credit in the same database
transaction. Deposits use a system funding account as the balancing side.
Ledger entries are append-only. A reversal creates new entries rather than
editing history. A database trigger enforces append-only behavior.

### Idempotency keys

- `id`
- key
- request fingerprint
- status
- stored response
- timestamps

A unique index prevents concurrent requests with the same key from creating
independent claims. Reusing a key with a different payload returns an error
rather than changing the original operation. The prototype currently uses a
global key namespace; API-key ownership and tenant scoping are not implemented.

### API keys

- `id`
- optional name
- SHA-256 key digest
- optional revocation timestamp
- timestamps

The raw API key is returned only when it is created and is never stored.
Clients send it in the `X-API-Key` header for every `/v1` request. Missing,
invalid, or revoked keys receive `401 Unauthorized`.

### Database integrity

The schema uses foreign keys, `NOT NULL` constraints, check constraints, and
unique indexes for invariants that must hold regardless of which code path
writes to the database. Application transactions additionally enforce balanced
transfers and materialized-balance rules.

## Key design decisions

### Integer cents instead of floating point

Money is represented as integer minor units plus a currency code. This avoids
binary floating-point rounding and makes equality, constraints, and ledger
balancing explicit. Invalid or non-positive transfer amounts are rejected before
the transaction is attempted.

### Row locks instead of serializable isolation

Transfers lock the affected account rows with `SELECT ... FOR UPDATE`, update
them in a consistent order, and write both ledger entries in one transaction.
This targets only the records involved in a transfer instead of making every
request run at serializable isolation.

Serialization failures and deadlocks that can be retried safely use bounded
transaction retries. Requests that cannot be safely retried fail explicitly.

### Idempotency at the database boundary

The unique idempotency-key index is the final protection against duplicate
operations. Application-level checks alone are insufficient because two
concurrent requests can pass a pre-check before either commits.

### Materialized balances with reconciliation

The service stores `accounts.balance_cents` as a materialized value and updates
it in the same transaction as the ledger entries. This keeps balance reads
inexpensive while PostgreSQL remains the source of truth. Reconciliation
compares the materialized balance with the sum of the append-only ledger entries
and records drift without silently repairing it.

### Append-only history

Historical ledger entries are not edited to correct mistakes. Corrections are
represented by new entries, preserving an auditable sequence of events.

## Testing strategy

Tests cover both business behavior and database invariants:

- Unit tests for amount, currency, authentication, and request validation
- Request tests for accounts, deposits, transfers, balances, and pagination
- Integration tests verifying atomic debit and credit writes
- Constraint tests for foreign keys, non-null fields, valid amounts, and
  uniqueness
- Idempotency tests showing that retries return the original response
- Negative idempotency tests showing that a changed payload is rejected
- Reversal tests proving that history is extended rather than edited
- Reconciliation tests for matching balances and drift detection
- Authentication tests

### Concurrency tests

The concurrency suite runs real requests against PostgreSQL:

1. Start with an account containing a known balance.
2. Submit 100 concurrent withdrawals whose total requested amount exceeds the
   balance.
3. Assert that the account never becomes negative.
4. Assert that the committed ledger entries balance to zero and match the
   account balance.
5. Submit concurrent requests using one idempotency key.
6. Assert that exactly one transfer is created and every successful retry
   returns the same stored result.
7. Run simultaneous transfers in both directions between the same two accounts.
8. Assert that requests do not deadlock, updates are not lost, and every
   committed transfer remains balanced.

These tests demonstrate guarantees that ordinary sequential request tests cannot
prove.

## CI

GitHub Actions runs the test suite against PostgreSQL and enforces formatting
and security checks. Database setup happens in CI so constraint and concurrency
tests run against the same database engine used in development.

The CI workflow runs:

- RSpec
- RuboCop
- Brakeman
- Bundler Audit

Testing and validation commands:

```bash
bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

Reconciliation runs daily at 2:00 AM through Solid Queue.

## Limitations and future scale considerations

The current prototype uses a global API-key namespace and does not implement
account-level authorization. It also does not provide production operational
controls such as rate limiting, structured logs, metrics, audit logging, or
deployment automation.

The initial design keeps PostgreSQL as the source of truth and uses row-level
locking. At larger scale, possible changes include:

- An outbox pattern for reliable publication of transfer events and webhooks
- Partitioning or sharding strategies for ledger and audit data
- Read replicas for carefully selected read workloads
- A dedicated reconciliation pipeline with incremental checkpoints
- Key rotation, authorization, rate limiting, and incident-recovery controls
- Online schema migrations and retention policies for large append-only tables
- Explicit multi-region consistency requirements before introducing regional
  writes

These changes would add operational complexity and would need to preserve the
same accounting invariants rather than bypassing them for throughput.

## Future work

- Webhooks for transfer events with signed payloads and retries
- Holds and authorizations
- Audit logging and structured operational telemetry
- Production deployment and measured load testing
