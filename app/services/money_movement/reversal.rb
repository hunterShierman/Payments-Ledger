module MoneyMovement
  # Reverses a completed transfer by creating a new, offsetting transfer.
  class Reversal
    MAX_ATTEMPTS = 3
    RETRY_BACKOFFS = [ 0.01, 0.02 ].freeze

    class InvalidTransfer < StandardError; end
    class AlreadyReversed < StandardError; end
    class InsufficientFunds < StandardError; end

    def self.call(transfer:)
      new(transfer:).call
    end

    def initialize(transfer:)
      @transfer = transfer
    end

    def call
      validate!

      attempts = 0
      begin
        attempts += 1
        reverse
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

    def reverse
      ::Transfer.transaction do
        transfer = ::Transfer.lock.find(@transfer.id)
        raise AlreadyReversed, "Transfer has already been reversed" if transfer.reversal
        raise InvalidTransfer, "Only completed transfers can be reversed" unless transfer.status == "completed"

        accounts = Account.where(
          id: [ transfer.source_account_id, transfer.destination_account_id ]
        ).order(:id).lock.index_by(&:id)
        source_account = accounts.fetch(transfer.destination_account_id)
        destination_account = accounts.fetch(transfer.source_account_id)
        if !source_account.system? && source_account.balance_cents < transfer.amount_cents
          raise InsufficientFunds, "Insufficient funds to reverse transfer"
        end

        reversal = ::Transfer.create!(
          source_account:,
          destination_account:,
          amount_cents: transfer.amount_cents,
          currency: transfer.currency,
          status: "completed",
          reversal_of_transfer: transfer
        )
        source_account.decrement!(:balance_cents, transfer.amount_cents)
        destination_account.increment!(:balance_cents, transfer.amount_cents)
        LedgerEntry.create!(
          account: source_account,
          transfer: reversal,
          amount_cents: -transfer.amount_cents,
          currency: transfer.currency,
          entry_type: "debit"
        )
        LedgerEntry.create!(
          account: destination_account,
          transfer: reversal,
          amount_cents: transfer.amount_cents,
          currency: transfer.currency,
          entry_type: "credit"
        )
        transfer.update!(status: "reversed")
        reversal
      end
    end

    def validate!
      raise InvalidTransfer, "Transfer not found" unless @transfer.is_a?(::Transfer) && @transfer.persisted?
    end
  end
end
