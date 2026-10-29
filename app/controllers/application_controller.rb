class ApplicationController < ActionController::API
  before_action :authenticate_api_key!

  private

  def authenticate_api_key!
    return if ApiKey.authenticate(request.headers["X-API-Key"])

    response.set_header("WWW-Authenticate", "X-API-Key")
    render json: { errors: [ "Valid X-API-Key header is required" ] }, status: :unauthorized
  end
end
