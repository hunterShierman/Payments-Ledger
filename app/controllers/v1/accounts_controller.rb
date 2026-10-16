module V1
  class AccountsController < ApplicationController
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

    def create
      account = Account.new(account_params)

      if account.save
        render json: account.as_json(only: %i[id currency balance_cents]), status: :created
      else
        render json: { errors: account.errors.full_messages }, status: :unprocessable_content
      end
    end

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

    private

    def account_params
      params.require(:account).permit(:currency)
    end

    def deposit_params
      params.require(:deposit).permit(:amount_cents, :currency)
    end

    def render_parameter_missing(error)
      render json: { errors: [ error.message ] }, status: :bad_request
    end
  end
end
