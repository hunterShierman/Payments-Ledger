module MoneyMovement
  # Moves money between two accounts while preserving the balance and
  # double-entry ledger invariants.
  class Transfer
    MAX_ATTEMPTS = 3
    RETRY_BACKOFFS = [ 0.01, 0.02 ].freeze

    class InvalidAmount < StandardError; end
    class CurrencyMismatch < StandardError; end
    class SameAccount < StandardError; end
    class InsufficientFunds < StandardError; end
    class UnknownAccount < StandardError; end

    # Transfers a positive amount atomically and returns the completed transfer.
    #
    # Both accounts are locked in ID order to serialize conflicting transfers.
    # Transient serialization, deadlock, and connection failures are retried
    # with bounded backoff; validation and business-rule failures are not retried.
    #
    # @param source_account [Account] account to debit
    # @param destination_account [Account] account to credit
    # @param amount_cents [Integer, String] positive amount in cents
    # @param currency [String] three-letter currency code matching both accounts
    # @return [::Transfer] the persisted transfer with two ledger entries
    # @raise [InvalidAmount] if the amount is not positive
    # @raise [CurrencyMismatch] if the currency does not match either account
    # @raise [SameAccount] if both account references identify the same account
    # @raise [InsufficientFunds] if a non-system source lacks sufficient funds
    # @raise [UnknownAccount] if either account does not exist
    def self.call(source_account:, destination_account:, amount_cents:, currency:)
      new(
        source_account:,
        destination_account:,
        amount_cents:,
        currency:
      ).call
    end

    # Stores the transfer inputs and normalizes the amount to integer cents.
    def initialize(source_account:, destination_account:, amount_cents:, currency:)
      @source_account = source_account
      @destination_account = destination_account
      @amount_cents = amount_cents.is_a?(String) ? Integer(amount_cents, 10) : Integer(amount_cents)
      @currency = currency
    rescue ArgumentError, TypeError
      @amount_cents = nil
    end

    # Validates the request and retries the transactional transfer when safe.
    def call
      validate!

      attempts = 0
      begin
        attempts += 1
        transfer
      rescue ActiveRecord::SerializationFailure,
        ActiveRecord::Deadlocked,
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::ConnectionFailed => error
        raise error if attempts >= MAX_ATTEMPTS

        Kernel.sleep RETRY_BACKOFFS.fetch(attempts - 1)
        retry
      end
    end

    private

    # Locks accounts, updates balances, and writes the balanced transfer entries.
    def transfer
      Account.transaction do
        # Lock in a consistent order so A-to-B and B-to-A transfers cannot
        # deadlock while acquiring the same pair of account locks.
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

    # Rejects invalid account references, amounts, account pairs, and currencies.
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

    # Checks that the supplied value is a persisted Account record.
    def account_reference_valid?(account)
      account.is_a?(Account) && account.persisted?
    end

    # Checks that both accounts use the requested transfer currency.
    def accounts_match_currency?(source_account, destination_account)
      source_account.currency == @currency && destination_account.currency == @currency
    end
  end
end
