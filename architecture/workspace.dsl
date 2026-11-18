workspace "Payments Ledger" "Architecture views for the Payments Ledger service." {

    model {
        client = person "API client" "A client that creates accounts, deposits funds, reads balances, and submits transfers."

        paymentsLedger = softwareSystem "Payments Ledger" "A double-entry payments ledger service that keeps balances correct under concurrent requests, makes retries safe, and preserves transaction history."

        client -> paymentsLedger "Uses the REST API over HTTPS"

        api = container paymentsLedger "Rails API" "API-only Rails application for authentication, request validation, money movement, balance reads, reversals, and cursor pagination." "Ruby on Rails"
        ledgerDatabase = container paymentsLedger "Ledger PostgreSQL database" "Transactional source of truth for accounts, materialized balances, transfers, append-only ledger entries, idempotency records, API keys, and reconciliation results." "PostgreSQL"
        queueDatabase = container paymentsLedger "Queue PostgreSQL database" "Stores Solid Queue job state and recurring reconciliation schedules." "PostgreSQL"
        reconciliationWorker = container paymentsLedger "Reconciliation worker" "Runs scheduled Rails reconciliation jobs to compare materialized balances with append-only ledger totals and record drift." "ActiveJob + Solid Queue"

        client -> api "Creates accounts, deposits funds, reads balances, submits transfers, reverses transfers, and lists account activity"
        api -> ledgerDatabase "Reads and writes accounts and ledger state through transactional SQL"
        reconciliationWorker -> ledgerDatabase "Reads balances and ledger entries and writes reconciliation checks"
        reconciliationWorker -> queueDatabase "Claims and updates scheduled jobs"
    }

    views {
        systemContext paymentsLedger "C1_SystemContext" {
            include client
            include paymentsLedger
            autolayout lr
            description "C1: System context for the Payments Ledger service."
            title "Payments Ledger - System Context"
        }

        container paymentsLedger "C2_Containers" {
            include client
            include api
            include ledgerDatabase
            include queueDatabase
            include reconciliationWorker
            autolayout lr
            description "C2: Containers inside the Payments Ledger service."
            title "Payments Ledger - Containers"
        }

        styles {
            element "Person" {
                background #08427b
                color #ffffff
                shape person
            }

            element "Software System" {
                background #1168bd
                color #ffffff
            }

            element "Container" {
                background #438dd5
                color #ffffff
            }

            element "External" {
                background #999999
                color #ffffff
            }
        }
    }
}
