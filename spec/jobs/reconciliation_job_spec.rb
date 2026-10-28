require "rails_helper"

RSpec.describe ReconciliationJob do
  let!(:account) { Account.create!(currency: "CAD") }

  describe "#perform" do
    it "records a balanced check for every account" do
      ReconciliationJob.perform_now

      check = ReconciliationCheck.find_by!(account:)
      expect(check).to have_attributes(
        stored_balance_cents: 0,
        ledger_balance_cents: 0,
        difference_cents: 0,
        status: "balanced"
      )
      expect(check.checked_at).to be_present
    end

    it "records drift without repairing the stored balance" do
      account.update_columns(balance_cents: 4_500)

      ReconciliationJob.perform_now

      check = ReconciliationCheck.find_by!(account:)
      expect(check).to have_attributes(
        stored_balance_cents: 4_500,
        ledger_balance_cents: 0,
        difference_cents: 4_500,
        status: "drifted"
      )
      expect(account.reload.balance_cents).to eq(4_500)
    end

    it "records a balanced account when its ledger entries sum to its balance" do
      account.update_columns(balance_cents: 0)

      ReconciliationJob.perform_now

      expect(ReconciliationCheck.find_by!(account:)).to have_attributes(
        stored_balance_cents: 0,
        ledger_balance_cents: 0,
        difference_cents: 0,
        status: "balanced"
      )
    end
  end
end
