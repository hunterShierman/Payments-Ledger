require "rails_helper"

RSpec.describe "API authentication", type: :request do
  describe "GET /v1/accounts/:id/balance" do
    it "rejects a request without an API key" do
      get "/v1/accounts/0/balance"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("errors" => [ "Valid X-API-Key header is required" ])
    end

    it "rejects an invalid API key" do
      get "/v1/accounts/0/balance", headers: { "X-API-Key" => "invalid" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "allows a request with a valid API key" do
      _api_key, raw_key = ApiKey.issue!

      get "/v1/accounts/0/balance", headers: { "X-API-Key" => raw_key }

      expect(response).to have_http_status(:not_found)
    end
  end
end
