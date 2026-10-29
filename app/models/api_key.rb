require "digest"
require "securerandom"

# Stores API keys as one-way digests and never persists the raw credential.
class ApiKey < ApplicationRecord
  validates :key_digest, presence: true, uniqueness: true

  class << self
    def issue!(name: nil)
      raw_key = SecureRandom.hex(32)
      [ create!(name:, key_digest: digest(raw_key)), raw_key ]
    end

    def authenticate(raw_key)
      return if raw_key.blank?

      find_by(key_digest: digest(raw_key), revoked_at: nil)
    end

    def digest(raw_key)
      Digest::SHA256.hexdigest(raw_key)
    end
  end
end
