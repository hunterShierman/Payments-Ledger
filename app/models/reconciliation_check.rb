class ReconciliationCheck < ApplicationRecord
  belongs_to :account

  STATUSES = %w[balanced drifted].freeze

  validates :stored_balance_cents, :ledger_balance_cents, :difference_cents,
    numericality: { only_integer: true }
  validates :status, inclusion: { in: STATUSES }
  validates :checked_at, presence: true
end
