class IdempotencyKey < ApplicationRecord
  STATUSES = %w[in_progress completed failed].freeze

  validates :key, presence: true, uniqueness: true
  validates :request_fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }
end
