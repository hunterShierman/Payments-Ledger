class CreateTransfers < ActiveRecord::Migration[8.1]
  # Creates transfer records and indexes account-to-account movement lookups.
  def change
    create_table :transfers do |t|
      t.references :source_account, null: false, foreign_key: { to_table: :accounts }
      t.references :destination_account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :amount_cents, null: false
      t.string :currency, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :request_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :transfers, [ :source_account_id, :destination_account_id ]
  end
end
