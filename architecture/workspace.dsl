workspace "Payments Ledger" "Target architecture views for the Payments Ledger service." {

    model {
        client = person "API client" "A client that creates accounts, deposits funds, reads balances, and submits transfers."
        operator = person "Operator" "A maintainer who reviews audit logs, reconciliation results, metrics, and structured logs."
        loadTester = softwareSystem "k6 load tests" "A k6 workload used to measure transfer throughput and balance-read latency." "External"

        paymentsLedger = softwareSystem "Payments Ledger" "A double-entry payments ledger service that keeps balances correct under concurrent requests, makes retries safe, and preserves an auditable history."

        client -> paymentsLedger "Uses the REST API over HTTPS"
        operator -> paymentsLedger "Reviews operational state and reconciliation results"
        loadTester -> paymentsLedger "Generates authenticated API traffic over HTTPS"

        api = container paymentsLedger "Rails API" "API-only Rails application for authentication, validation, money-movement commands, balance reads, pagination, audit logging, and structured request logging." "Ruby on Rails"
        database = container paymentsLedger "PostgreSQL" "Transactional source of truth for accounts, materialized balances, transfers, append-only ledger entries, idempotency records, audit logs, and reconciliation results." "PostgreSQL"
        jobs = container paymentsLedger "Reconciliation jobs" "Rails-native background jobs that recompute account balances from ledger entries and record drift." "ActiveJob + Solid Queue"

        client -> api "Creates accounts, deposits funds, reads balances, submits transfers, and lists ledger entries"
        operator -> api "Queries operational and audit endpoints"
        loadTester -> api "Runs load-test scenarios"
        api -> database "Reads and writes through transactional SQL"
        jobs -> database "Reads ledger entries and records reconciliation results"
        api -> jobs "Enqueues reconciliation work"
    }

    views {
        systemContext paymentsLedger "C1_SystemContext" {
            include client
            include operator
            include loadTester
            include paymentsLedger
            autolayout lr
            description "C1: System context for the Payments Ledger service."
            title "Payments Ledger - System Context"
        }

        container paymentsLedger "C2_Containers" {
            include client
            include operator
            include loadTester
            include api
            include database
            include jobs
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
