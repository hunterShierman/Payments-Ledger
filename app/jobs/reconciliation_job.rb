class ReconciliationJob < ApplicationJob
  def perform
    checked_at = Time.current

    Account.find_each do |account|
      stored_balance_cents = account.balance_cents
      ledger_balance_cents = account.ledger_entries.sum(:amount_cents)
      difference_cents = stored_balance_cents - ledger_balance_cents

      ReconciliationCheck.create!(
        account:,
        stored_balance_cents:,
        ledger_balance_cents:,
        difference_cents:,
        status: difference_cents.zero? ? "balanced" : "drifted",
        checked_at:
      )
    end
  end
end
