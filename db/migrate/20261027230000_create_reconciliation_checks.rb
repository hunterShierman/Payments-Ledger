class CreateReconciliationChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciliation_checks do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :stored_balance_cents, null: false
      t.bigint :ledger_balance_cents, null: false
      t.bigint :difference_cents, null: false
      t.string :status, null: false
      t.datetime :checked_at, null: false

      t.timestamps
    end

    add_index :reconciliation_checks, :checked_at
    add_index :reconciliation_checks, [ :account_id, :checked_at ]
  end
end
