require "rails_helper"

RSpec.describe "Transfers API", type: :request do
  let!(:api_key) { ApiKey.issue!.last }
  let(:api_headers) { { "X-API-Key" => api_key } }
  let!(:source_account) { Account.create!(currency: "CAD", balance_cents: 5_000) }
  let!(:destination_account) { Account.create!(currency: "CAD") }

  describe "POST /v1/transfers" do
    let(:transfer_params) do
      {
        transfer: {
          source_account_id: source_account.id,
          destination_account_id: destination_account.id,
          amount_cents: 1_200,
          currency: "CAD"
        }
      }
    end

    it "creates a transfer and returns its details" do
      post "/v1/transfers", params: transfer_params,
        headers: api_headers.merge("Idempotency-Key" => "transfer-1")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        "id" => be_present,
        "source_account_id" => source_account.id,
        "destination_account_id" => destination_account.id,
        "amount_cents" => 1_200,
        "currency" => "CAD",
        "status" => "completed"
      )
      expect(source_account.reload.balance_cents).to eq(3_800)
      expect(destination_account.reload.balance_cents).to eq(1_200)
      expect(Transfer.count).to eq(1)
      expect(LedgerEntry.count).to eq(2)
    end

    it "rejects insufficient funds" do
      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { amount_cents: 5_001 }),
        headers: api_headers.merge("Idempotency-Key" => "transfer-insufficient")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Insufficient funds" ])
      expect(Transfer.count).to eq(0)
      expect(LedgerEntry.count).to eq(0)
    end

    it "rejects a same-account transfer" do
      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { destination_account_id: source_account.id }),
        headers: api_headers.merge("Idempotency-Key" => "transfer-same-account")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        "errors" => [ "Source and destination accounts must differ" ]
      )
    end

    it "rejects a currency mismatch" do
      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { currency: "USD" }),
        headers: api_headers.merge("Idempotency-Key" => "transfer-currency")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Currency does not match account" ])
    end

    it "returns not found for an unknown account" do
      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { destination_account_id: 0 }),
        headers: api_headers.merge("Idempotency-Key" => "transfer-unknown")

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq("errors" => [ "Account not found" ])
    end

    it "rejects an invalid amount" do
      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { amount_cents: 0 }),
        headers: api_headers.merge("Idempotency-Key" => "transfer-invalid-amount")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("errors" => [ "Amount must be greater than 0" ])
    end

    it "requires the transfer payload" do
      post "/v1/transfers", params: {}, headers: api_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq(
        "errors" => [ "param is missing or the value is empty or invalid: transfer" ]
      )
    end

    it "requires an idempotency key" do
      post "/v1/transfers", params: transfer_params, headers: api_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq(
        "errors" => [ "Idempotency-Key header is required" ]
      )
    end

    it "replays a transfer response without creating a second transfer" do
      headers = api_headers.merge("Idempotency-Key" => "transfer-replay")
      post "/v1/transfers", params: transfer_params, headers: headers
      first_response = response.parsed_body

      post "/v1/transfers", params: transfer_params, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq(first_response)
      expect(Transfer.count).to eq(1)
      expect(LedgerEntry.count).to eq(2)
    end

    it "rejects a changed payload with the same idempotency key" do
      headers = api_headers.merge("Idempotency-Key" => "transfer-conflict")
      post "/v1/transfers", params: transfer_params, headers: headers

      post "/v1/transfers",
        params: transfer_params.deep_merge(transfer: { amount_cents: 200 }),
        headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq(
        "errors" => [ "Idempotency key was used with a different request" ]
      )
      expect(Transfer.count).to eq(1)
    end

    describe "POST /v1/transfers/:id/reversal" do
      let!(:transfer) do
        MoneyMovement::Transfer.call(
          source_account:,
          destination_account:,
          amount_cents: 1_200,
          currency: "CAD"
        )
      end

      it "creates an offsetting transfer" do
        post "/v1/transfers/#{transfer.id}/reversal",
          headers: api_headers.merge("Idempotency-Key" => "reversal-1")

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include(
          "source_account_id" => destination_account.id,
          "destination_account_id" => source_account.id,
          "amount_cents" => 1_200,
          "currency" => "CAD",
          "status" => "completed",
          "reversal_of_transfer_id" => transfer.id
        )
        expect(transfer.reload.status).to eq("reversed")
      end

      it "rejects a second reversal" do
        headers = api_headers.merge("Idempotency-Key" => "reversal-2")
        post "/v1/transfers/#{transfer.id}/reversal", headers: headers
        post "/v1/transfers/#{transfer.id}/reversal",
          headers: api_headers.merge("Idempotency-Key" => "reversal-3")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq("errors" => [ "Transfer has already been reversed" ])
      end

      it "requires an idempotency key" do
        post "/v1/transfers/#{transfer.id}/reversal", headers: api_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to eq("errors" => [ "Idempotency-Key header is required" ])
      end

      it "returns not found for an unknown transfer" do
        post "/v1/transfers/0/reversal",
          headers: api_headers.merge("Idempotency-Key" => "reversal-missing")

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("errors" => [ "Transfer not found" ])
      end
    end
  end
end
