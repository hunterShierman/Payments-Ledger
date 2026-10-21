module MoneyMovement
  class Deposit
    InvalidAmount = Transfer::InvalidAmount
    CurrencyMismatch = Transfer::CurrencyMismatch

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
        funding_account = Account.find_or_create_by!(currency: @currency, system: true)

        MoneyMovement::Transfer.call(
          source_account: funding_account,
          destination_account: @account,
          amount_cents: @amount_cents,
          currency: @currency
        )
      end
    end

    private

    def validate!
      raise InvalidAmount, "Amount must be greater than 0" unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
      raise CurrencyMismatch, "Currency does not match account" unless @account.currency == @currency
    end
  end
end
