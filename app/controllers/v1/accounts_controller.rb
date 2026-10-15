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

    private

    def account_params
      params.require(:account).permit(:currency)
    end

    def render_parameter_missing(error)
      render json: { errors: [ error.message ] }, status: :bad_request
    end
  end
end
