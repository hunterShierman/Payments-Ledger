class CreateLedgerEntries < ActiveRecord::Migration[8.1]
  # Creates signed ledger entries associated with accounts and transfers.
  def change
    create_table :ledger_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :transfer, null: false, foreign_key: true
      t.bigint :amount_cents, null: false
      t.string :currency, null: false
      t.string :entry_type, null: false

      t.timestamps
    end

    add_index :ledger_entries, [ :account_id, :created_at ]
  end
end
