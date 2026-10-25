# A customer or system account whose balance is maintained in minor currency units.
#
# The materialized balance is updated in the same transaction as ledger entries.
# System accounts may temporarily go negative when they fund customer deposits.
class Account < ApplicationRecord
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :source_account_id,
    dependent: :restrict_with_exception
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :destination_account_id,
    dependent: :restrict_with_exception
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
end
