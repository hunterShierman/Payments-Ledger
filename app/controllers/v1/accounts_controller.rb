module V1
  # Exposes account creation, deposits, and materialized balance reads.
  class AccountsController < ApplicationController
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

    # Creates an account with a zero materialized balance.
    #
    # @return [void] renders the account or validation errors as JSON
    def create
      account = Account.new(account_params)

      if account.save
        render json: account.as_json(only: %i[id currency balance_cents]), status: :created
      else
        render json: { errors: account.errors.full_messages }, status: :unprocessable_content
      end
    end

    # Deposits funds through the shared balanced money-movement service.
    #
    # @return [void] renders the resulting transfer and refreshed balance as JSON
    def deposits
      account = Account.find(params[:id])
      transfer = MoneyMovement::Deposit.call(
        account:,
        amount_cents: deposit_params[:amount_cents],
        currency: deposit_params[:currency]
      )

      render json: {
        account_id: account.id,
        amount_cents: transfer.amount_cents,
        currency: transfer.currency,
        balance_cents: account.reload.balance_cents
      }, status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { errors: [ "Account not found" ] }, status: :not_found
    rescue MoneyMovement::Deposit::InvalidAmount, MoneyMovement::Deposit::CurrencyMismatch => error
      render json: { errors: [ error.message ] }, status: :unprocessable_content
    rescue ActiveRecord::RecordInvalid => error
      render json: { errors: error.record.errors.full_messages }, status: :unprocessable_content
    end

    # Reads the account's transactionally maintained materialized balance.
    #
    # @return [void] renders the account ID, currency, and balance as JSON
    def balance
      account = Account.find(params[:id])

      render json: {
        account_id: account.id,
        currency: account.currency,
        balance_cents: account.balance_cents
      }
    rescue ActiveRecord::RecordNotFound
      render json: { errors: [ "Account not found" ] }, status: :not_found
    end

    private

    # Permits the currency field accepted by account creation.
    def account_params
      params.require(:account).permit(:currency)
    end

    # Permits the amount and currency fields accepted by deposits.
    def deposit_params
      params.require(:deposit).permit(:amount_cents, :currency)
    end

    # Renders missing required request parameters as a bad-request response.
    def render_parameter_missing(error)
      render json: { errors: [ error.message ] }, status: :bad_request
    end
  end
end
