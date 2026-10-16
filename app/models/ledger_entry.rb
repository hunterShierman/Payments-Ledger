class LedgerEntry < ApplicationRecord
  belongs_to :account
  belongs_to :transfer

  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :entry_type, presence: true
end
