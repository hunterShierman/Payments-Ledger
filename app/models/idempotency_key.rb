# Stores the fingerprint and response needed to safely retry a transfer request.
#
# A key moves from in_progress to completed or failed. The unique key constraint
# ensures concurrent requests cannot claim the same operation independently.
class IdempotencyKey < ApplicationRecord
  STATUSES = %w[in_progress completed failed].freeze

  validates :key, presence: true, uniqueness: true
  validates :request_fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }
end
