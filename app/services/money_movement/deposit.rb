module MoneyMovement
  class Deposit
    class InvalidAmount < StandardError; end
    class CurrencyMismatch < StandardError; end

    def self.call(account:, amount_cents:, currency:)
      new(account:, amount_cents:, currency:).call
    end

    def initialize(account:, amount_cents:, currency:)
      @account = account
      @amount_cents = amount_cents.is_a?(String) ? Integer(amount_cents, 10) : Integer(amount_cents)
      @currency = currency
    rescue ArgumentError, TypeError
      @amount_cents = nil
    end

    def call
      validate!

      Account.transaction do
        customer_account = Account.lock.find(@account.id)
        funding_account = Account.lock.find_or_create_by!(currency: @currency, system: true)
        transfer = Transfer.create!(
          source_account: funding_account,
          destination_account: customer_account,
          amount_cents: @amount_cents,
          currency: @currency,
          status: "completed"
        )

        customer_account.increment!(:balance_cents, @amount_cents)
        funding_account.decrement!(:balance_cents, @amount_cents)
        LedgerEntry.create!(
          account: funding_account,
          transfer:,
          amount_cents: -@amount_cents,
          currency: @currency,
          entry_type: "debit"
        )
        LedgerEntry.create!(
          account: customer_account,
          transfer:,
          amount_cents: @amount_cents,
          currency: @currency,
          entry_type: "credit"
        )

        transfer
      end
    end

    private

    def validate!
      raise InvalidAmount, "Amount must be greater than 0" unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
      raise CurrencyMismatch, "Currency does not match account" unless @account.currency == @currency
    end
  end
end
