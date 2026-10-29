require "rails_helper"

RSpec.describe "Balances API", type: :request do
  let!(:api_key) { ApiKey.issue!.last }
  let(:api_headers) { { "X-API-Key" => api_key } }
  let!(:account) { Account.create!(currency: "CAD") }

  describe "GET /v1/accounts/:id/balance" do
    it "returns the materialized account balance" do
      MoneyMovement::Deposit.call(account:, amount_cents: 5_000, currency: "CAD")

      get "/v1/accounts/#{account.id}/balance", headers: api_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "account_id" => account.id,
        "currency" => "CAD",
        "balance_cents" => 5_000
      )
      expect(account.reload.balance_cents).to eq(account.ledger_entries.sum(:amount_cents))
    end

    it "returns a zero balance for a new account" do
      get "/v1/accounts/#{account.id}/balance", headers: api_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "account_id" => account.id,
        "currency" => "CAD",
        "balance_cents" => 0
      )
    end

    it "returns not found for an unknown account" do
      get "/v1/accounts/0/balance", headers: api_headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("errors" => [ "Account not found" ])
    end
  end
end
