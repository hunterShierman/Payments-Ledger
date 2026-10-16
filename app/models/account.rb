class Account < ApplicationRecord
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :source_account_id,
    dependent: :restrict_with_exception
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :destination_account_id,
    dependent: :restrict_with_exception
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
end
