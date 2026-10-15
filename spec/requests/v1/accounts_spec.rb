require "rails_helper"

RSpec.describe "Accounts API", type: :request do
  describe "POST /v1/accounts" do
    it "creates a zero-balance account" do
      post "/v1/accounts", params: { account: { currency: "CAD" } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "id" => be_present,
        "currency" => "CAD",
        "balance_cents" => 0
      )
      expect(Account.count).to eq(1)
    end

    it "rejects a lowercase currency" do
      post "/v1/accounts", params: { account: { currency: "cad" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Currency is invalid" ])
      expect(Account.count).to eq(0)
    end

    it "rejects a currency that is not three letters" do
      post "/v1/accounts", params: { account: { currency: "US" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Currency is invalid" ])
    end

    it "rejects a missing currency" do
      post "/v1/accounts", params: { account: { currency: nil } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Currency can't be blank", "Currency is invalid" ])
    end

    it "does not permit a client-supplied opening balance" do
      post "/v1/accounts", params: { account: { currency: "USD", balance_cents: 10_000 } }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["balance_cents"]).to eq(0)
    end

    it "requires the account payload" do
      post "/v1/accounts", params: { currency: "USD" }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("errors" => [ "param is missing or the value is empty or invalid: account" ])
    end
  end
end
