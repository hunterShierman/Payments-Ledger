class AddDomainCheckConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :accounts, "currency ~ '^[A-Z]{3}$'",
      name: "accounts_currency_format"
    add_check_constraint :transfers, "currency ~ '^[A-Z]{3}$'",
      name: "transfers_currency_format"
    add_check_constraint :transfers, "status IN ('pending', 'completed', 'reversed')",
      name: "transfers_status_allowed"
    add_check_constraint :ledger_entries, "currency ~ '^[A-Z]{3}$'",
      name: "ledger_entries_currency_format"
    add_check_constraint :ledger_entries,
      "(entry_type = 'debit' AND amount_cents < 0) OR (entry_type = 'credit' AND amount_cents > 0)",
      name: "ledger_entries_entry_type_sign"
    add_check_constraint :reconciliation_checks, "status IN ('balanced', 'drifted')",
      name: "reconciliation_checks_status_allowed"
    add_check_constraint :idempotency_keys, "status IN ('in_progress', 'completed', 'failed')",
      name: "idempotency_keys_status_allowed"
  end
end
