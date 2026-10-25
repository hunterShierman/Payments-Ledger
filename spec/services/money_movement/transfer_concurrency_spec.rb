require "rails_helper"

RSpec.describe MoneyMovement::Transfer, :concurrency, use_transactional_fixtures: false do
  before do
    clean_database
  end

  after do
    clean_database
  end

  it "allows only one concurrent withdrawal when both requests see the same balance" do
    source_account = Account.create!(currency: "CAD", balance_cents: 1_000)
    destination_accounts = 2.times.map { Account.create!(currency: "CAD") }
    start_gate = Queue.new
    results = Queue.new

    threads = destination_accounts.map do |destination_account|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start_gate.pop
          results << begin
            described_class.call(
              source_account: Account.find(source_account.id),
              destination_account: Account.find(destination_account.id),
              amount_cents: 600,
              currency: "CAD"
            )
            :success
          rescue MoneyMovement::Transfer::InsufficientFunds
            :insufficient_funds
          end
        end
      end
    end

    2.times { start_gate << true }
    threads.each(&:join)

    expect(2.times.map { results.pop }).to contain_exactly(:success, :insufficient_funds)
    expect(source_account.reload.balance_cents).to eq(400)
    expect(source_account.ledger_entries.sum(:amount_cents)).to eq(-600)
  end

  def clean_database
    ActiveRecord::Base.connection.execute(
      "TRUNCATE ledger_entries, transfers, accounts RESTART IDENTITY CASCADE"
    )
  end
end
