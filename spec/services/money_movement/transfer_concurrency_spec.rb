require "rails_helper"
require "timeout"

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
    expect(source_account.balance_cents).to be >= 0
    expect(source_account.ledger_entries.sum(:amount_cents)).to eq(-600)
    expect(source_account.balance_cents - 1_000).to eq(source_account.ledger_entries.sum(:amount_cents))
    expect(destination_accounts.sum { |account| account.reload.balance_cents }).to eq(600)
    expect(destination_accounts.sum { |account| account.ledger_entries.sum(:amount_cents) }).to eq(600)
    expect(Transfer.count).to eq(1)
  end

  it "completes simultaneous transfers in opposite directions without deadlock" do
    account_a = Account.create!(currency: "CAD", balance_cents: 1_000)
    account_b = Account.create!(currency: "CAD", balance_cents: 1_000)
    start_gate = Queue.new
    results = Queue.new

    requests = [
      [ account_a.id, account_b.id ],
      [ account_b.id, account_a.id ]
    ]
    threads = requests.map do |source_id, destination_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start_gate.pop
          results << begin
            described_class.call(
              source_account: Account.find(source_id),
              destination_account: Account.find(destination_id),
              amount_cents: 100,
              currency: "CAD"
            )
            :success
          rescue StandardError => error
            error
          end
        end
      end
    end

    2.times { start_gate << true }
    Timeout.timeout(10) { threads.each(&:join) }

    outcomes = 2.times.map { results.pop }
    expect(outcomes).to all eq(:success)
    expect(Transfer.count).to eq(2)
    expect(Transfer.all).to all satisfy { |transfer| transfer.ledger_entries.sum(:amount_cents).zero? }
    expect(account_a.reload.balance_cents).to eq(1_000)
    expect(account_b.reload.balance_cents).to eq(1_000)
    expect(account_a.ledger_entries.sum(:amount_cents)).to eq(0)
    expect(account_b.ledger_entries.sum(:amount_cents)).to eq(0)
    expect(LedgerEntry.sum(:amount_cents)).to eq(0)
  end

  it "never overdraws an account across 100 concurrent withdrawals" do
    source_account = Account.create!(currency: "CAD", balance_cents: 5_000)
    destination_accounts = 100.times.map { Account.create!(currency: "CAD") }
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
              amount_cents: 100,
              currency: "CAD"
            )
            :success
          rescue MoneyMovement::Transfer::InsufficientFunds
            :insufficient_funds
          rescue StandardError => error
            error
          end
        end
      end
    end

    destination_accounts.length.times { start_gate << true }
    Timeout.timeout(30) { threads.each(&:join) }

    outcomes = destination_accounts.length.times.map { results.pop }
    successful_withdrawals = outcomes.count(:success)
    expect(outcomes).to all(be_a(Symbol))
    expect(successful_withdrawals).to eq(50)
    expect(outcomes.count(:insufficient_funds)).to eq(50)
    expect(source_account.reload.balance_cents).to eq(0)
    expect(source_account.balance_cents).to be >= 0
    expect(source_account.ledger_entries.sum(:amount_cents)).to eq(-successful_withdrawals * 100)
    expect(source_account.balance_cents - 5_000).to eq(source_account.ledger_entries.sum(:amount_cents))
    expect(Transfer.count).to eq(successful_withdrawals)
  end

  def clean_database
    ActiveRecord::Base.connection.execute(
      "TRUNCATE ledger_entries, transfers, accounts RESTART IDENTITY CASCADE"
    )
  end
end
