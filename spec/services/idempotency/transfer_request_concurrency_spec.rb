require "rails_helper"
require "timeout"

RSpec.describe Idempotency::TransferRequest, :concurrency, use_transactional_fixtures: false do
  before do
    clean_database
  end

  after do
    clean_database
  end

  it "creates one transfer when requests with the same key run concurrently" do
    source_account = Account.create!(currency: "CAD", balance_cents: 1_000)
    destination_account = Account.create!(currency: "CAD")
    request_params = {
      "source_account_id" => source_account.id,
      "destination_account_id" => destination_account.id,
      "amount_cents" => 600,
      "currency" => "CAD"
    }
    start_gate = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start_gate.pop
          results << begin
            described_class.call(key: "concurrent-transfer", request_params:) do
              transfer = MoneyMovement::Transfer.call(
                source_account: Account.find(source_account.id),
                destination_account: Account.find(destination_account.id),
                amount_cents: request_params["amount_cents"],
                currency: request_params["currency"]
              )
              [
                :created,
                transfer.as_json(
                  only: %i[id source_account_id destination_account_id amount_cents currency status]
                )
              ]
            end
          rescue StandardError => error
            error
          end
        end
      end
    end

    2.times { start_gate << true }
    Timeout.timeout(10) { threads.each(&:join) }

    outcomes = 2.times.map { results.pop }

    expect(outcomes).to all(be_a(described_class::Result))
    expect(outcomes.map(&:status)).to all(eq(201))
    expect(outcomes.map(&:body)).to all(eq(outcomes.first.body))
    expect(Transfer.count).to eq(1)
    expect(IdempotencyKey.count).to eq(1)

    stored_key = IdempotencyKey.find_by!(key: "concurrent-transfer")
    expect(stored_key.status).to eq("completed")
    expect(stored_key.response_status).to eq(201)
    expect(stored_key.response_body).to eq(outcomes.first.body)
    expect(source_account.reload.balance_cents).to eq(400)
    expect(destination_account.reload.balance_cents).to eq(600)
  end

  private

  def clean_database
    ActiveRecord::Base.connection.execute(
      "TRUNCATE ledger_entries, transfers, accounts, idempotency_keys RESTART IDENTITY CASCADE"
    )
  end
end
