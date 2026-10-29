class AddPaginationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :ledger_entries, [ :account_id, :created_at, :id ]
    add_index :transfers, [ :source_account_id, :created_at, :id ]
    add_index :transfers, [ :destination_account_id, :created_at, :id ]
  end
end
