class Account < ApplicationRecord
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
end
