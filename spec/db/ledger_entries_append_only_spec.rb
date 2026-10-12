require "rails_helper"

RSpec.describe "ledger entries append-only trigger", type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.execute <<~SQL
      INSERT INTO accounts (currency, balance_cents, created_at, updated_at)
      VALUES ('USD', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             ('USD', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL

    connection.execute <<~SQL
      INSERT INTO transfers (
        source_account_id, destination_account_id, amount_cents, currency,
        status, request_metadata, created_at, updated_at
      )
      SELECT MIN(id), MAX(id), 100, 'USD', 'pending', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM accounts
    SQL
  end

  before do
    connection.execute <<~SQL
      INSERT INTO ledger_entries (
        account_id, transfer_id, amount_cents, currency, entry_type,
        created_at, updated_at
      )
      SELECT MIN(accounts.id), MAX(transfers.id), 100, 'USD', 'debit',
             CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM accounts, transfers
    SQL
  end

  context "when an existing entry is updated" do
    it "rejects the update" do
      expect do
        connection.execute <<~SQL
          UPDATE ledger_entries
          SET amount_cents = 200
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /ledger_entries is append-only/)
    end
  end

  context "when an existing entry is deleted" do
    it "rejects the delete" do
      expect do
        connection.execute("DELETE FROM ledger_entries")
      end.to raise_error(ActiveRecord::StatementInvalid, /ledger_entries is append-only/)
    end
  end
end
