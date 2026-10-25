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

    it "rolls back the transfer and balances when the second entry write fails" do
      entry_writes = 0
      allow(LedgerEntry).to receive(:create!).and_wrap_original do |original, *args|
        entry_writes += 1
        raise ActiveRecord::RecordInvalid, LedgerEntry.new if entry_writes == 2

        original.call(*args)
      end

      expect do
        described_class.call(
          source_account:,
          destination_account:,
          amount_cents: 1_200,
          currency: "CAD"
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(entry_writes).to eq(2)
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

    it "rejects a same-account transfer without writing anything" do
      expect do
        described_class.call(
          source_account:,
          destination_account: source_account,
          amount_cents: 100,
          currency: "CAD"
        )
      end.to raise_error(MoneyMovement::Transfer::SameAccount, "Source and destination accounts must differ")

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(source_account.reload.balance_cents).to eq(5_000)
    end

    it "rejects an unknown account without writing anything" do
      unknown_account = Account.new(id: 99_999, currency: "CAD")

      expect do
        described_class.call(
          source_account:,
          destination_account: unknown_account,
          amount_cents: 100,
          currency: "CAD"
        )
      end.to raise_error(MoneyMovement::Transfer::UnknownAccount, "Source or destination account not found")

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(source_account.reload.balance_cents).to eq(5_000)
    end

    it "rejects an invalid amount without writing anything" do
      expect do
        described_class.call(
          source_account:,
          destination_account:,
          amount_cents: 0,
          currency: "CAD"
        )
      end.to raise_error(MoneyMovement::Transfer::InvalidAmount, "Amount must be greater than 0")

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(source_account.reload.balance_cents).to eq(5_000)
    end

    it "rejects a transfer that exceeds the source balance without writing anything" do
      expect do
        described_class.call(
          source_account:,
          destination_account:,
          amount_cents: 5_001,
          currency: "CAD"
        )
      end.to raise_error(MoneyMovement::Transfer::InsufficientFunds, "Insufficient funds")

      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(source_account.reload.balance_cents).to eq(5_000)
      expect(destination_account.reload.balance_cents).to eq(0)
    end

    it "allows the system funding account to go negative for deposits" do
      funding_account = Account.create!(currency: "CAD", system: true)

      described_class.call(
        source_account: funding_account,
        destination_account:,
        amount_cents: 100,
        currency: "CAD"
      )

      expect(funding_account.reload.balance_cents).to eq(-100)
      expect(destination_account.reload.balance_cents).to eq(100)
    end
  end
end
