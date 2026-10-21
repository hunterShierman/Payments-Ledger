require "rails_helper"

RSpec.describe MoneyMovement::Transfer do
  let!(:source_account) { Account.create!(currency: "CAD", balance_cents: 5_000) }
  let!(:destination_account) { Account.create!(currency: "CAD") }

  describe ".call" do
    it "updates balances and creates balanced ledger entries atomically" do
      transfer = described_class.call(
        source_account:,
        destination_account:,
        amount_cents: 1_200,
        currency: "CAD"
      )

      expect(transfer).to be_persisted
      expect(source_account.reload.balance_cents).to eq(3_800)
      expect(destination_account.reload.balance_cents).to eq(1_200)
      expect(transfer.ledger_entries.pluck(:amount_cents)).to contain_exactly(-1_200, 1_200)
      expect(LedgerEntry.where(transfer:).sum(:amount_cents)).to eq(0)
      expect(source_account.ledger_entries.sum(:amount_cents)).to eq(source_account.balance_cents - 5_000)
      expect(destination_account.ledger_entries.sum(:amount_cents)).to eq(destination_account.balance_cents)
    end

    it "rolls back the transfer and balances when an entry write fails" do
      allow(LedgerEntry).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        described_class.call(
          source_account:,
          destination_account:,
          amount_cents: 1_200,
          currency: "CAD"
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(source_account.reload.balance_cents).to eq(5_000)
      expect(destination_account.reload.balance_cents).to eq(0)
    end

    it "rejects a currency mismatch without writing anything" do
      expect do
        described_class.call(
          source_account:,
          destination_account:,
          amount_cents: 100,
          currency: "USD"
        )
      end.to raise_error(MoneyMovement::Transfer::CurrencyMismatch)

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
    end
  end
end
