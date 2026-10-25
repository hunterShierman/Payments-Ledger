module MoneyMovement
  # Funds an account through a balanced transfer from a system account.
  class Deposit
    InvalidAmount = Transfer::InvalidAmount
    CurrencyMismatch = Transfer::CurrencyMismatch

    # Deposits a positive amount and returns the resulting funding transfer.
    #
    # A per-currency system account supplies the funds, so the deposit creates
    # both sides of the ledger entry in the same database transaction.
    #
    # @param account [Account] customer account receiving the funds
    # @param amount_cents [Integer, String] positive amount in cents
    # @param currency [String] currency matching the account
    # @return [::Transfer] the persisted funding transfer
    # @raise [InvalidAmount] if the amount is not positive
    # @raise [CurrencyMismatch] if the currency does not match the account
    def self.call(account:, amount_cents:, currency:)
      new(account:, amount_cents:, currency:).call
    end

    # Stores the deposit inputs and normalizes the amount to integer cents.
    def initialize(account:, amount_cents:, currency:)
      @account = account
      @amount_cents = amount_cents.is_a?(String) ? Integer(amount_cents, 10) : Integer(amount_cents)
      @currency = currency
    rescue ArgumentError, TypeError
      @amount_cents = nil
    end

    # Validates the deposit and funds the account through a system transfer.
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

    # Rejects non-positive amounts and currencies that differ from the account.
    def validate!
      raise InvalidAmount, "Amount must be greater than 0" unless @amount_cents.is_a?(Integer) && @amount_cents.positive?
      raise CurrencyMismatch, "Currency does not match account" unless @account.currency == @currency
    end
  end
end
