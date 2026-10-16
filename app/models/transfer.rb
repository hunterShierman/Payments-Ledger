class Transfer < ApplicationRecord
  belongs_to :source_account, class_name: "Account"
  belongs_to :destination_account, class_name: "Account"
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :source_account, comparison: { other_than: :destination_account }
end
