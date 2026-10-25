require "rails_helper"

RSpec.describe Idempotency::TransferRequest do
  let(:params) { { "amount_cents" => 100, "currency" => "CAD" } }

  it "executes once and replays the stored response" do
    # The block represents the money movement that must run only on the first claim.
    executions = 0
    execute = lambda do
      executions += 1
      [ :created, { "transfer_id" => 12 } ]
    end

    first = described_class.call(key: "key-1", request_params: params, &execute)
    second = described_class.call(key: "key-1", request_params: params, &execute)

    expect(first).to eq(second)
    expect(executions).to eq(1)
    expect(IdempotencyKey.find_by!(key: "key-1").response_body).to eq("transfer_id" => 12)
  end

  it "rejects the same key with a different payload" do
    described_class.call(key: "key-1", request_params: params) { [ :created, {} ] }

    expect do
      described_class.call(
        key: "key-1",
        request_params: params.merge("amount_cents" => 200)
      ) { [ :created, {} ] }
    end.to raise_error(described_class::Conflict)
  end

  it "requires an idempotency key" do
    expect do
      described_class.call(key: "", request_params: params) { [ :created, {} ] }
    end.to raise_error(described_class::MissingKey)
  end

  it "stores validation responses for replay" do
    execute = lambda { [ :unprocessable_content, { "errors" => [ "Invalid amount" ] } ] }

    described_class.call(key: "key-1", request_params: params, &execute)
    replay = described_class.call(key: "key-1", request_params: params, &execute)

    expect(replay.status).to eq(422)
    expect(replay.body).to eq("errors" => [ "Invalid amount" ])
  end

  it "allows a failed request to be retried with the same key" do
    expect do
      described_class.call(key: "key-1", request_params: params) { raise "interrupted" }
    end.to raise_error("interrupted")

    result = described_class.call(key: "key-1", request_params: params) { [ :created, { "transfer_id" => 12 } ] }

    expect(result.status).to eq(201)
    expect(IdempotencyKey.find_by!(key: "key-1").status).to eq("completed")
  end
end
