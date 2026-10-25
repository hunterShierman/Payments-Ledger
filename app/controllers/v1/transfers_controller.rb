module V1
  # Exposes idempotent account-to-account transfers over the v1 API.
  class TransfersController < ApplicationController
    rescue_from ActionController::ParameterMissing, with: :render_parameter_missing

    # Creates a transfer and returns the stored response for an idempotent retry.
    #
    # @return [void] renders a JSON response with the transfer or validation error
    # @raise [Idempotency::TransferRequest::MissingKey] when the header is absent
    def create
      result = Idempotency::TransferRequest.call(
        key: request.headers["Idempotency-Key"],
        request_params: transfer_params.to_h
      ) do
        execute_transfer
      end

      render json: result.body, status: result.status
    rescue Idempotency::TransferRequest::MissingKey => error
      render json: { errors: [ error.message ] }, status: :unprocessable_content
    rescue Idempotency::TransferRequest::Conflict, Idempotency::TransferRequest::InProgress => error
      render json: { errors: [ error.message ] }, status: :conflict
    end

    private

    # Executes the domain transfer and converts known failures into API results.
    def execute_transfer
      transfer = MoneyMovement::Transfer.call(
        source_account: Account.find(transfer_params[:source_account_id]),
        destination_account: Account.find(transfer_params[:destination_account_id]),
        amount_cents: transfer_params[:amount_cents],
        currency: transfer_params[:currency]
      )

      [
        :created,
        transfer.as_json(only: %i[id source_account_id destination_account_id amount_cents currency status])
      ]
    rescue ActiveRecord::RecordNotFound
      [ :not_found, { errors: [ "Account not found" ] } ]
    rescue MoneyMovement::Transfer::InvalidAmount,
      MoneyMovement::Transfer::CurrencyMismatch,
      MoneyMovement::Transfer::SameAccount,
      MoneyMovement::Transfer::InsufficientFunds,
      MoneyMovement::Transfer::UnknownAccount => error
      [ :unprocessable_content, { errors: [ error.message ] } ]
    rescue ActiveRecord::RecordInvalid => error
      [ :unprocessable_content, { errors: error.record.errors.full_messages } ]
    end

    # Permits the fields accepted by the transfer endpoint.
    def transfer_params
      params.require(:transfer).permit(
        :source_account_id,
        :destination_account_id,
        :amount_cents,
        :currency
      )
    end

    # Renders missing required request parameters as a bad-request response.
    def render_parameter_missing(error)
      render json: { errors: [ error.message ] }, status: :bad_request
    end
  end
end
