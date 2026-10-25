# Architecture decisions

## Row locks over serializable isolation

### Context

Transfers update two materialized account balances and create a transfer with
one debit and one credit ledger entry. Concurrent transfers can touch the same
accounts, including transfers in opposite directions. The operation must not
allow an overdraft, lose a balance update, or leave partially written ledger
data.

### Decision

The money-movement service uses a database transaction and locks every affected
account row with `SELECT ... FOR UPDATE`. It acquires those locks in ascending
account ID order, then checks the locked balances, updates both balances, and
writes the transfer and ledger entries before committing. Transient deadlocks,
serialization failures, and connection failures are retried with bounded
attempts and backoff.

### Why row locks

Row locks protect the specific mutable resources involved in a transfer. A
withdrawal waits for another transaction holding the same source account lock,
then evaluates the current committed balance instead of acting on a stale
snapshot. Unrelated accounts can continue transferring without being forced
through a database-wide serialization check.

This also makes the business rule visible in the service: accounts are locked
before the insufficient-funds check. Locking both accounts in a deterministic
order prevents the usual A-to-B versus B-to-A lock cycle, while still allowing
the database to detect and report an unexpected deadlock.

### Tradeoffs

Row locks make contention explicit. Transfers sharing an account are
serialized, so a busy account can become a throughput bottleneck and requests
may wait for the transaction holding its lock. Transactions must therefore
stay short, and the service must avoid doing external work while locks are
held.

Serializable isolation offers a broader guarantee: the database checks whether
the transaction could have run in a serial order and aborts it when concurrent
work conflicts. That can protect code paths that touch a wider or less
predictable set of rows, but it also creates more serialization failures and
requires retrying whole transactions. It does not remove contention; it moves
conflict detection to commit time and can make failures less predictable as
the transaction grows.

For this service, the affected rows are known up front and the invariant is
account-local. Explicit row locks provide the needed protection with narrower
contention and a straightforward retry boundary. Serializable isolation
remains an option if future operations depend on predicates or sets of rows
that cannot be locked explicitly, but that would be a deliberate change with
additional retry and load testing.

### Failure modes

A transaction that cannot obtain a lock immediately may wait, and a long
transaction can increase latency for every transfer involving that account.
The consistent lock order prevents the expected bidirectional deadlock, but
deadlocks can still arise from future code that acquires other locks in a
different order. PostgreSQL may also raise serialization or connection errors
while the transaction is in progress. The service retries only those
transient failures, with a bounded attempt count; after the limit it surfaces
the error rather than risking an unbounded request.

Business failures such as invalid amounts, currency mismatches, and
insufficient funds are not retried. They are deterministic for the request,
and retrying them would add load without changing the outcome. Because all
balance and ledger writes are inside the same transaction, an error during
any write rolls back the transfer, balance changes, and ledger entries
together.
