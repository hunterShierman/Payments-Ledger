require "rails_helper"

RSpec.describe ApiKey, type: :model do
  describe ".issue!" do
    it "returns a raw key while storing only its digest" do
      api_key, raw_key = described_class.issue!(name: "test client")

      expect(raw_key).to be_present
      expect(api_key.name).to eq("test client")
      expect(api_key.key_digest).to eq(described_class.digest(raw_key))
      expect(api_key.key_digest).not_to eq(raw_key)
      expect(described_class.authenticate(raw_key)).to eq(api_key)
    end
  end

  describe ".authenticate" do
    it "does not authenticate a revoked key" do
      api_key, raw_key = described_class.issue!
      api_key.update!(revoked_at: Time.current)

      expect(described_class.authenticate(raw_key)).to be_nil
    end
  end
end
