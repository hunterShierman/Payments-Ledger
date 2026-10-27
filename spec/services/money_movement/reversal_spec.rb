require "rails_helper"

RSpec.describe MoneyMovement::Reversal do
  let!(:source_account) { Account.create!(currency: "CAD", balance_cents: 5_000) }
  let!(:destination_account) { Account.create!(currency: "CAD") }
  let!(:transfer) do
    MoneyMovement::Transfer.call(
      source_account:,
      destination_account:,
      amount_cents: 1_200,
      currency: "CAD"
    )
  end

  describe ".call" do
    it "creates an offsetting transfer without changing the original entries" do
      original_entries = transfer.ledger_entries.pluck(:account_id, :amount_cents, :entry_type)

      reversal = described_class.call(transfer:)

      expect(reversal).to be_persisted
      expect(reversal.reversal_of_transfer).to eq(transfer)
      expect(transfer.reload.status).to eq("reversed")
      expect(transfer.ledger_entries.pluck(:account_id, :amount_cents, :entry_type)).to eq(original_entries)
      expect(reversal.ledger_entries.pluck(:amount_cents)).to contain_exactly(-1_200, 1_200)
      expect(source_account.reload.balance_cents).to eq(5_000)
      expect(destination_account.reload.balance_cents).to eq(0)
      expect(LedgerEntry.where(transfer:).sum(:amount_cents)).to eq(0)
      expect(LedgerEntry.where(transfer: reversal).sum(:amount_cents)).to eq(0)
    end

    it "rejects a second reversal" do
      described_class.call(transfer:)

      expect { described_class.call(transfer:) }.to raise_error(
        described_class::AlreadyReversed,
        "Transfer has already been reversed"
      )
    end

    it "rolls back when a reversal entry write fails" do
      entry_writes = 0
      allow(LedgerEntry).to receive(:create!).and_wrap_original do |original, *args|
        entry_writes += 1
        raise ActiveRecord::RecordInvalid, LedgerEntry.new if entry_writes == 2

        original.call(*args)
      end

      expect { described_class.call(transfer:) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(transfer.reload.status).to eq("completed")
      expect(transfer.reversal).to be_nil
      expect(Transfer.count).to eq(1)
      expect(LedgerEntry.count).to eq(2)
      expect(source_account.reload.balance_cents).to eq(3_800)
      expect(destination_account.reload.balance_cents).to eq(1_200)
    end
  end
end
