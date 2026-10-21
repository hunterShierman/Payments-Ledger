module MoneyMovement
  class Transfer
    class InvalidAmount < StandardError; end
    class CurrencyMismatch < StandardError; end
    class SameAccount < StandardError; end
    class InsufficientFunds < StandardError; end
    class UnknownAccount < StandardError; end

    def self.call(source_account:, destination_account:, amount_cents:, currency:)
      new(
        source_account:,
        destination_account:,
        amount_cents:,
        currency:
      ).call
    end

    def initialize(source_account:, destination_account:, amount_cents:, currency:)
      @source_account = source_account
      @destination_account = destination_account
      @amount_cents = amount_cents.is_a?(String) ? Integer(amount_cents, 10) : Integer(amount_cents)
      @currency = currency
    rescue ArgumentError, TypeError
      @amount_cents = nil
    end

    def call
      validate!

      Account.transaction do
        accounts = Account.where(id: [ @source_account.id, @destination_account.id ]).order(:id).lock
          .index_by(&:id)
        source_account = accounts[@source_account.id]
        destination_account = accounts[@destination_account.id]
        raise UnknownAccount, "Source or destination account not found" unless source_account && destination_account
        raise CurrencyMismatch, "Currency does not match account" unless accounts_match_currency?(source_account, destination_account)

        if !source_account.system? && source_account.balance_cents < @amount_cents
          raise InsufficientFunds, "Insufficient funds"
        end

        transfer = ::Transfer.create!(
          source_account:,
          destination_account:,
          amount_cents: @amount_cents,
          currency: @currency,
          status: "completed"
        )

        source_account.decrement!(:balance_cents, @amount_cents)
        destination_account.increment!(:balance_cents, @amount_cents)
        LedgerEntry.create!(
          account: source_account,
          transfer:,
          amount_cents: -@amount_cents,
          currency: @currency,
          entry_type: "debit"
        )
        LedgerEntry.create!(
          account: destination_account,
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
      unless account_reference_valid?(@source_account) && account_reference_valid?(@destination_account)
        raise UnknownAccount, "Source or destination account not found"
      end
      raise SameAccount, "Source and destination accounts must differ" if @source_account.id == @destination_account.id
      unless accounts_match_currency?(@source_account, @destination_account)
        raise CurrencyMismatch, "Currency does not match account"
      end
    end

    def account_reference_valid?(account)
      account.is_a?(Account) && account.persisted?
    end

    def accounts_match_currency?(source_account, destination_account)
      source_account.currency == @currency && destination_account.currency == @currency
    end
  end
end
