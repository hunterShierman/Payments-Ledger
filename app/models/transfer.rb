# A business money-movement operation between two distinct accounts.
#
# Each persisted transfer is expected to have one debit and one credit
# LedgerEntry created in the same transaction.
class Transfer < ApplicationRecord
  belongs_to :source_account, class_name: "Account"
  belongs_to :destination_account, class_name: "Account"
  belongs_to :reversal_of_transfer, class_name: "Transfer", optional: true
  has_one :reversal, class_name: "Transfer", foreign_key: :reversal_of_transfer_id,
    dependent: :restrict_with_exception
  has_many :ledger_entries, dependent: :restrict_with_exception

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :source_account, comparison: { other_than: :destination_account }
  validates :reversal_of_transfer, uniqueness: true, allow_nil: true
end
