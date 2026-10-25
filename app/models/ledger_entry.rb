# An append-only, signed account-perspective entry for a transfer.
#
# Debits are negative and credits are positive. Corrections must be represented
# by new entries, preserving the historical sequence of accounting events.
class LedgerEntry < ApplicationRecord
  belongs_to :account
  belongs_to :transfer

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :entry_type, presence: true
end
