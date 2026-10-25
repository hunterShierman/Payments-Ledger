class AddIntegrityCheckConstraints < ActiveRecord::Migration[8.1]
  # Adds database-level checks for valid transfer and ledger amounts.
  def change
    # These rules must hold for direct SQL writes as well as application writes.
    add_check_constraint :transfers, "amount_cents > 0", name: "transfers_amount_cents_positive"
    add_check_constraint :transfers, "source_account_id <> destination_account_id",
      name: "transfers_source_and_destination_different"
    add_check_constraint :ledger_entries, "amount_cents <> 0", name: "ledger_entries_amount_cents_nonzero"
  end
end
