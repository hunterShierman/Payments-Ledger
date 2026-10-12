require "rails_helper"

RSpec.describe "database integrity check constraints", type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.execute <<~SQL
      INSERT INTO accounts (currency, balance_cents, created_at, updated_at)
      VALUES ('USD', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
             ('USD', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  it "rejects transfers with a non-positive amount" do
    expect do
      connection.execute <<~SQL
        INSERT INTO transfers (
          source_account_id, destination_account_id, amount_cents, currency,
          status, request_metadata, created_at, updated_at
        )
        SELECT MIN(id), MAX(id), 0, 'USD', 'pending', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM accounts
      SQL
    end.to raise_error(ActiveRecord::StatementInvalid, /transfers_amount_cents_positive/)
  end

  it "rejects transfers whose source and destination are the same account" do
    expect do
      connection.execute <<~SQL
        INSERT INTO transfers (
          source_account_id, destination_account_id, amount_cents, currency,
          status, request_metadata, created_at, updated_at
        )
        SELECT MIN(id), MIN(id), 100, 'USD', 'pending', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM accounts
      SQL
    end.to raise_error(ActiveRecord::StatementInvalid, /transfers_source_and_destination_different/)
  end

  it "rejects ledger entries with a zero amount" do
    connection.execute <<~SQL
      INSERT INTO transfers (
        source_account_id, destination_account_id, amount_cents, currency,
        status, request_metadata, created_at, updated_at
      )
      SELECT MIN(id), MAX(id), 100, 'USD', 'pending', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM accounts
    SQL

    expect do
      connection.execute <<~SQL
        INSERT INTO ledger_entries (
          account_id, transfer_id, amount_cents, currency, entry_type,
          created_at, updated_at
        )
        SELECT MIN(id), (SELECT MAX(id) FROM transfers), 0, 'USD', 'debit',
               CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM accounts
      SQL
    end.to raise_error(ActiveRecord::StatementInvalid, /ledger_entries_amount_cents_nonzero/)
  end
end
