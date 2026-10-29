require "rails_helper"

RSpec.describe "Account pagination API", type: :request do
  let!(:api_key) { ApiKey.issue!.last }
  let(:headers) { { "X-API-Key" => api_key } }
  let!(:account) { Account.create!(currency: "CAD") }
  let!(:other_account) { Account.create!(currency: "CAD", balance_cents: 10_000) }

  def create_transfer(amount_cents)
    MoneyMovement::Transfer.call(
      source_account: other_account,
      destination_account: account,
      amount_cents:,
      currency: "CAD"
    )
  end

  describe "GET /v1/accounts/:id/ledger-entries" do
    it "returns stable pages without duplicates" do
      3.times { |index| create_transfer((index + 1) * 100) }

      get "/v1/accounts/#{account.id}/ledger-entries", params: { limit: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      first_page = response.parsed_body
      expect(first_page["data"].length).to eq(2)
      expect(first_page.dig("pagination", "has_more")).to be(true)

      get "/v1/accounts/#{account.id}/ledger-entries",
        params: { limit: 2, cursor: first_page.dig("pagination", "next_cursor") },
        headers: headers

      second_page = response.parsed_body
      expect(second_page["data"].length).to eq(1)
      expect(second_page["data"].map { |entry| entry["id"] }).not_to include(
        first_page["data"].first["id"],
        first_page["data"].second["id"]
      )
      expect(second_page.dig("pagination", "has_more")).to be(false)
    end

    it "rejects an invalid cursor" do
      get "/v1/accounts/#{account.id}/ledger-entries",
        params: { cursor: "invalid" }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("errors" => [ "cursor is invalid" ])
    end
  end

  describe "GET /v1/accounts/:id/transfers" do
    it "includes transfers involving the account" do
      create_transfer(100)

      get "/v1/accounts/#{account.id}/transfers", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].first).to include(
        "source_account_id" => other_account.id,
        "destination_account_id" => account.id,
        "amount_cents" => 100
      )
    end
  end
end
