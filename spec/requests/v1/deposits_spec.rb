require "rails_helper"

RSpec.describe "Deposits API", type: :request do
  let!(:account) { Account.create!(currency: "CAD") }

  describe "POST /v1/accounts/:id/deposits" do
    it "creates balanced ledger entries and updates the account balance" do
      post "/v1/accounts/#{account.id}/deposits",
        params: { deposit: { amount_cents: 5_000, currency: "CAD" } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "account_id" => account.id,
        "amount_cents" => 5_000,
        "currency" => "CAD",
        "balance_cents" => 5_000
      )
      expect(account.reload.balance_cents).to eq(5_000)
      expect(Transfer.count).to eq(1)
      expect(LedgerEntry.count).to eq(2)
      expect(LedgerEntry.sum(:amount_cents)).to eq(0)
      expect(Account.where(system: true).count).to eq(1)
    end

    it "rejects a non-positive amount without writing anything" do
      post "/v1/accounts/#{account.id}/deposits",
        params: { deposit: { amount_cents: 0, currency: "CAD" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
      expect(account.reload.balance_cents).to eq(0)
    end

    it "rejects a currency mismatch without writing anything" do
      post "/v1/accounts/#{account.id}/deposits",
        params: { deposit: { amount_cents: 100, currency: "USD" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
    end

    it "does not allow an unknown account to receive a deposit" do
      post "/v1/accounts/0/deposits",
        params: { deposit: { amount_cents: 100, currency: "CAD" } }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("errors" => [ "Account not found" ])
    end

    it "requires the deposit payload" do
      post "/v1/accounts/#{account.id}/deposits", params: {}

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq(
        "errors" => [ "param is missing or the value is empty or invalid: deposit" ]
      )
    end
  end
end
