# Payments Ledger

[![CI](https://github.com/hunterShierman/Payments-Ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/hunterShierman/Payments-Ledger/actions/workflows/ci.yml)

Payments Ledger is a double-entry payments ledger service designed to make every
cent traceable, transfers safe to retry, and balances correct under concurrent
requests.

The project focuses on backend correctness rather than CRUD breadth. PostgreSQL is the source of truth for accounts, transfers, ledger entries, and
balances. The central invariant is that a committed transfer has equal debit and
credit entries, so the ledger always sums to zero.

This is a personal project and is not connected to any employer or production
payment system.

## Implemented

The current implementation includes:

- Account creation, deposits, and balance reads
- Double-entry transfers with integer-cent amounts
- Database-enforced amount, account, and append-only ledger constraints
- Idempotency-key replay and payload-conflict handling for transfers
- Row locking and bounded retries for concurrent money movement
- Immutable transfer reversals represented by compensating entries
- Reconciliation drift checks through Solid Queue
- Hashed API-key authentication for the v1 API
- Cursor pagination for account ledger entries and transfers
- Request, service, database, and PostgreSQL-backed concurrency specs
- GitHub Actions checks for RSpec, RuboCop, Brakeman, and Bundler Audit

## Deferred

- Transfer reads by ID
- Audit logging
- Structured JSON logging and metrics
- Authorization and account/tenant ownership
- Load testing and published performance results
- Production deployment
- Webhooks, holds, and authorizations

## Project boundary

Payments Ledger is an educational, correctness-focused prototype rather than
production payment infrastructure. It demonstrates transactional money
movement, double-entry accounting, safe request retries, database-enforced
invariants, and concurrency control. Production hardening would still require
authorization boundaries, rate limiting, stronger idempotency claim recovery,
consistent reconciliation snapshots, operational observability, deployment
controls, and incident-recovery procedures.

## Local checks

Run `bin/setup --skip-server` after cloning or updating the project. This
installs the dependencies, prepares the database, and enables the tracked
Git pre-commit hook.

The hook runs `bin/ci`, which checks the test database, RSpec suite, RuboCop,
Bundler Audit, and Brakeman before allowing a commit. To intentionally bypass
the checks for one commit, use Git's standard `--no-verify` option or set
`SKIP_PRE_COMMIT=1`.

### Local background jobs

Development uses Solid Queue with a local PostgreSQL queue database. Run
`SOLID_QUEUE_IN_PUMA=1 bin/dev` to start the web server and queue supervisor
together. Reconciliation is scheduled daily at 2:00 AM and runs without Redis.

## Architecture

The API-only Rails application validates requests and executes money-movement
commands. PostgreSQL owns transactional state and enforces invariants. API-key
authentication, reconciliation, and background processing are implemented with
Rails and PostgreSQL-native components.

The diagrams describe the current application boundary and the operational
components that may be added later.

### C1: System context

![Payments Ledger system context diagram](C1_SystemContext.svg)

### C2: Container view

![Payments Ledger container diagram](C2_Containers.svg)

The architecture is also maintained as Structurizr DSL in
[`architecture/workspace.dsl`](architecture/workspace.dsl), including the C1
system-context and C2 container views.

## Data model

The schema currently includes the entities below. Fields and future entities may
continue to evolve during implementation:

### `accounts`

- `id`
- `currency`
- `balance_cents`
- timestamps

`balance_cents` is an integer maintained transactionally with ledger writes. It
is the read path for balances. The reconciliation job checks it against the
account's ledger total and records drift without silently repairing the value.
The service does not use a cache in the initial implementation.

### `transfers`

- `id`
- source account
- destination account
- amount in cents
- currency
- status
- request metadata and timestamps

A transfer represents the business operation. Its state and response are the
basis for idempotent retries.

### `ledger_entries`

- `id`
- account
- transfer
- amount in cents, signed from the account's perspective
- currency
- entry type
- timestamps

Each money movement creates one debit and one credit in the same database
transaction. Deposits use a system funding account as the balancing side instead
of creating unbalanced money. Ledger entries are append-only. A reversal creates new entries instead of editing historical entries. Append-only
behavior is enforced with a database trigger rather than relying only on
application conventions.

### `idempotency_keys`

- idempotency key
- request fingerprint
- stored response
- timestamps

A unique index ensures that concurrent requests with the same key cannot create
independent claims. Reusing a key with a different payload returns an error
rather than silently changing the original operation. The prototype currently
uses a global key namespace; API-key ownership and tenant scoping are deferred.

### `api_keys`

- `id`
- optional name
- SHA-256 key digest
- optional revocation timestamp
- timestamps

The raw API key is returned only by `ApiKey.issue!` and is never stored. Clients
must send it in the `X-API-Key` header for every `/v1` request. Missing, invalid,
or revoked keys receive `401 Unauthorized`.

### Database integrity

The schema uses foreign keys, `NOT NULL` constraints, check constraints, and
unique indexes for invariants that must hold regardless of which code path
writes to the database. Application transactions additionally enforce the
balanced transfer and materialized-balance rules.

## API

The following endpoints are currently implemented:

- `POST /v1/accounts`
- `POST /v1/accounts/:id/deposits`
- `GET /v1/accounts/:id/balance`
- `GET /v1/accounts/:id/ledger-entries`
- `GET /v1/accounts/:id/transfers`
- `POST /v1/transfers`
- `POST /v1/transfers/:id/reversal`

Deposits and account-to-account transfers share the same transactional
money-movement service.

### Create an account

```http
POST /v1/accounts
X-API-Key: <api-key>
Content-Type: application/json

{
  "currency": "CAD"
}
```

```json
{
  "id": 1,
  "currency": "CAD",
  "balance_cents": 0
}
```

### Deposit funds

```http
POST /v1/accounts/1/deposits
X-API-Key: <api-key>
Content-Type: application/json

{
  "amount_cents": 5000,
  "currency": "CAD"
}
```

```json
{
  "account_id": 1,
  "amount_cents": 5000,
  "currency": "CAD",
  "balance_cents": 5000
}
```

Internally, this creates a balanced pair of entries between the system funding
account and the customer account.

### Read a balance

```http
GET /v1/accounts/1/balance
X-API-Key: <api-key>
```

```json
{
  "account_id": 1,
  "currency": "CAD",
  "balance_cents": 5000
}
```

### Create a transfer

```http
POST /v1/transfers
X-API-Key: <api-key>
Idempotency-Key: transfer-request-001
Content-Type: application/json

{
  "source_account_id": 1,
  "destination_account_id": 2,
  "amount_cents": 1250,
  "currency": "CAD"
}
```

```json
{
  "id": 1,
  "status": "completed",
  "source_account_id": 1,
  "destination_account_id": 2,
  "amount_cents": 1250,
  "currency": "CAD"
}
```

Retrying the request with the same idempotency key and payload returns the
stored result. The same key with a different payload returns a client error.
Insufficient funds also returns a client error and creates no partial transfer.

### Reverse a transfer

```http
POST /v1/transfers/1/reversal
X-API-Key: <api-key>
Idempotency-Key: reversal-request-001
```

Reversals create a new transfer with the source and destination swapped and
append offsetting ledger entries. The original transfer and its ledger entries
are never edited; a second reversal of the same transfer is rejected.

### Deferred: read a transfer

```http
GET /v1/transfers/1
X-API-Key: <api-key>
```

### List ledger entries and transfers

```http
GET /v1/accounts/1/ledger-entries?limit=50&cursor=<cursor>
X-API-Key: <api-key>
```

The transfers endpoint uses the same `limit` and `cursor` parameters:

```http
GET /v1/accounts/1/transfers?limit=50&cursor=<cursor>
X-API-Key: <api-key>
```

Both endpoints return records in ascending `(created_at, id)` order. The
compound ordering makes records with the same timestamp deterministic, while
the opaque cursor prevents duplicates across pages. `limit` defaults to 50 and
is capped at 100. Invalid cursors and limits return `400 Bad Request`.

## Key design decisions

### Integer cents instead of floating point

Money is represented as integer minor units plus a currency code. This
avoids binary floating-point rounding and makes equality, constraints, and
ledger balancing explicit. Amount validation will reject invalid or
non-positive transfer amounts before the transaction is attempted.

### Row locks instead of serializable isolation

Transfers lock the affected account rows with `SELECT ... FOR UPDATE`,
update them in a consistent order, and write both ledger entries in one
transaction. This targets the specific records involved in a transfer and
keeps contention more predictable than running every request at serializable
isolation.

Serialization failures and deadlocks that can be retried safely will use bounded
transaction retries. Requests that cannot be safely retried will fail explicitly.

### Idempotency at the database boundary

The unique idempotency-key index is the final protection against duplicate
operations. Application-level checks alone are insufficient because two
concurrent requests can both pass a pre-check before either commits.

### Materialized balances with reconciliation

The service stores `accounts.balance_cents` as a materialized value and
updates it in the same transaction as the ledger entries. This keeps balance
reads inexpensive while PostgreSQL remains the source of truth. Reconciliation
compares the materialized balance with the sum of the account's append-only
ledger entries and records drift without silently repairing it.

### Append-only history

Historical ledger entries are not edited to correct mistakes. Corrections are
represented by new entries, preserving an auditable sequence of events.

## Testing strategy

Tests will cover both business behavior and database invariants:

- Unit tests for amount, currency, authentication, and request validation
- Request tests for account, deposit, transfer, balance, and pagination APIs
- Integration tests verifying atomic debit/credit writes
- Constraint tests for foreign keys, non-null fields, valid amounts, and
  uniqueness
- Idempotency tests showing that retries return the original response
- Negative idempotency tests showing that a changed payload is rejected
- Reversal tests proving that history is extended rather than edited
- Reconciliation tests for matching balances and drift detection
- Authentication tests

### Concurrency tests

The most important tests will run real concurrent requests against PostgreSQL:

1. Start with an account containing a known balance.
2. Submit 100 concurrent withdrawals whose total requested amount exceeds that
   balance.
3. Assert that the account never becomes negative.
4. Assert that the committed ledger entries balance to zero and match the
   account balance.
5. Submit concurrent requests using one idempotency key.
6. Assert that exactly one transfer is created and every successful retry
   returns the same stored result.
7. Run simultaneous transfers in both directions between the same two accounts.
8. Assert that the requests do not deadlock, no updates are lost, and every
   committed transfer remains balanced.

These tests are intended to demonstrate the guarantees that ordinary sequential
request tests cannot prove.

## Code documentation convention

Public domain services use concise comments for non-obvious side effects,
invariants, parameters, return values, and domain-specific exceptions.

## Local development

Prerequisites:

- Ruby and Bundler
- PostgreSQL
- Node.js only if required by the selected Rails setup

The local workflow is:

```bash
git clone <repository-url>
cd payments-ledger
bundle install
bin/rails db:prepare
bin/rails server
```

Create a development API key and copy the printed value:

```bash
bin/rails runner 'key, raw = ApiKey.issue!(name: "local"); puts raw'
```

Send that value in the `X-API-Key` header when calling `/v1` endpoints.

Run the test suite with RSpec:

```bash
bundle exec rspec
```

Start the web server and local Solid Queue supervisor together with:

```bash
SOLID_QUEUE_IN_PUMA=1 bin/dev
```

## CI

GitHub Actions runs the test suite against PostgreSQL and enforces formatting
and security checks. Database setup happens in CI so constraint and concurrency
tests run against the same database engine used in development.

## Limitations and future scale considerations

This prototype intentionally uses a global API-key namespace and does not
implement account-level authorization. It also does not yet provide production
operational controls such as rate limiting, structured logs, metrics, audit
logging, or deployment automation. These are deliberate scope boundaries rather
than claims that the service is ready for production payment traffic.

The initial design intentionally keeps PostgreSQL as the source of truth and
uses row-level locking. At larger scale, I would evaluate:

- An outbox pattern for reliable publication of transfer events and webhooks
- Partitioning or sharding strategies for ledger and audit data
- Read replicas for carefully selected read workloads
- A dedicated reconciliation pipeline with incremental checkpoints
- Stronger operational controls for key rotation, authorization, rate limiting,
  and incident recovery
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
