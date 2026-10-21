module V1
  class TransfersController < ApplicationController
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

    def create
      transfer = MoneyMovement::Transfer.call(
        source_account: Account.find(transfer_params[:source_account_id]),
        destination_account: Account.find(transfer_params[:destination_account_id]),
        amount_cents: transfer_params[:amount_cents],
        currency: transfer_params[:currency]
      )

      render json: transfer.as_json(
        only: %i[id source_account_id destination_account_id amount_cents currency status]
      ), status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { errors: [ "Account not found" ] }, status: :not_found
    rescue MoneyMovement::Transfer::InvalidAmount,
      MoneyMovement::Transfer::CurrencyMismatch,
      MoneyMovement::Transfer::SameAccount,
      MoneyMovement::Transfer::InsufficientFunds,
      MoneyMovement::Transfer::UnknownAccount => error
      render json: { errors: [ error.message ] }, status: :unprocessable_content
    rescue ActiveRecord::RecordInvalid => error
      render json: { errors: error.record.errors.full_messages }, status: :unprocessable_content
    end

    private

    def transfer_params
      params.require(:transfer).permit(
        :source_account_id,
        :destination_account_id,
        :amount_cents,
        :currency
      )
    end

    def render_parameter_missing(error)
      render json: { errors: [ error.message ] }, status: :bad_request
    end
  end
end
