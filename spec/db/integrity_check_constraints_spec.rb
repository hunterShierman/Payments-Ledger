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

  describe "transfers" do
    context "when the amount is non-positive" do
      it "rejects the transfer" do
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
    end

    context "when the source and destination are the same account" do
      it "rejects the transfer" do
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
    end

    context "when the currency is not a three-letter uppercase code" do
      it "rejects the transfer" do
        expect do
          connection.execute <<~SQL
            INSERT INTO transfers (
              source_account_id, destination_account_id, amount_cents, currency,
              status, request_metadata, created_at, updated_at
            )
            SELECT MIN(id), MAX(id), 100, 'usd', 'pending', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM accounts
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /transfers_currency_format/)
      end
    end

    context "when the status is not allowed" do
      it "rejects the transfer" do
        expect do
          connection.execute <<~SQL
            INSERT INTO transfers (
              source_account_id, destination_account_id, amount_cents, currency,
              status, request_metadata, created_at, updated_at
            )
            SELECT MIN(id), MAX(id), 100, 'USD', 'unknown', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM accounts
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /transfers_status_allowed/)
      end
    end
  end

  describe "ledger entries" do
    context "when the amount is zero" do
      it "rejects the ledger entry" do
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

    context "when the currency is not a three-letter uppercase code" do
      it "rejects the ledger entry" do
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
            SELECT MIN(id), (SELECT MAX(id) FROM transfers), -100, 'usd', 'debit',
                   CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM accounts
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /ledger_entries_currency_format/)
      end
    end

    context "when the entry type does not match the amount sign" do
      it "rejects a debit with a positive amount" do
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
            SELECT MIN(id), (SELECT MAX(id) FROM transfers), 100, 'USD', 'debit',
                   CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM accounts
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /ledger_entries_entry_type_sign/)
      end
    end
  end

  describe "accounts" do
    context "when the currency is not a three-letter uppercase code" do
      it "rejects the account" do
        expect do
          connection.execute <<~SQL
            INSERT INTO accounts (currency, balance_cents, created_at, updated_at)
            VALUES ('US', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /accounts_currency_format/)
      end
    end
  end

  describe "reconciliation checks" do
    context "when the status is not allowed" do
      it "rejects the check" do
        expect do
          connection.execute <<~SQL
            INSERT INTO reconciliation_checks (
              account_id, stored_balance_cents, ledger_balance_cents, difference_cents,
              status, checked_at, created_at, updated_at
            )
            SELECT MIN(id), 0, 0, 0, 'unknown', CURRENT_TIMESTAMP,
                   CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM accounts
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /reconciliation_checks_status_allowed/)
      end
    end
  end

  describe "idempotency keys" do
    context "when the status is not allowed" do
      it "rejects the key" do
        expect do
          connection.execute <<~SQL
            INSERT INTO idempotency_keys (
              key, request_fingerprint, status, created_at, updated_at
            )
            VALUES ('invalid-status', 'fingerprint', 'unknown',
                    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
        end.to raise_error(ActiveRecord::StatementInvalid, /idempotency_keys_status_allowed/)
      end
    end
  end
end
