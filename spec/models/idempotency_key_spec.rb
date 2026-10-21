require "rails_helper"

RSpec.describe IdempotencyKey do
  subject(:idempotency_key) do
    described_class.new(
      key: "transfer-123",
      request_fingerprint: "fingerprint",
      status: "in_progress"
    )
  end

  it "is valid with a key and request fingerprint" do
    expect(idempotency_key).to be_valid
  end

  it "requires a key" do
    idempotency_key.key = nil

    expect(idempotency_key).not_to be_valid
    expect(idempotency_key.errors[:key]).to include("can't be blank")
  end

  it "requires a request fingerprint" do
    idempotency_key.request_fingerprint = nil

    expect(idempotency_key).not_to be_valid
    expect(idempotency_key.errors[:request_fingerprint]).to include("can't be blank")
  end

  it "only accepts supported statuses" do
    idempotency_key.status = "unknown"

    expect(idempotency_key).not_to be_valid
    expect(idempotency_key.errors[:status]).to include("is not included in the list")
  end

  it "enforces unique keys" do
    idempotency_key.save!
    duplicate = described_class.new(
      key: idempotency_key.key,
      request_fingerprint: "different-fingerprint"
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:key]).to include("has already been taken")
  end
end
