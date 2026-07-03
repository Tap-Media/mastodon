# frozen_string_literal: true

class Api::V1::Mobile::AuthController < Api::BaseController
  skip_before_action :require_authenticated_user!
  skip_before_action :require_not_suspended!

  def exchange
    one_time_code = params[:one_time_code]
    client_id = params[:client_id]
    redirect_uri = params[:redirect_uri]

    if one_time_code.blank? || client_id.blank? || redirect_uri.blank?
      render json: {
        error: 'invalid_request',
        error_code: 'invalid_exchange_request',
        error_description: 'one_time_code, client_id, and redirect_uri are required.'
      }, status: :bad_request
      return
    end

    # Fetch and atomically delete from cache
    cached_data = Rails.cache.delete("mobile_handoff:#{one_time_code}")

    if cached_data.nil?
      render json: {
        error: 'invalid_grant',
        error_code: 'handoff_code_invalid',
        error_description: 'The one_time_code is invalid, expired, or already used.'
      }, status: :bad_request
      return
    end

    # Validate client_id and redirect_uri match cached data
    if cached_data[:client_id] != client_id || cached_data[:redirect_uri] != redirect_uri
      render json: {
        error: 'invalid_grant',
        error_code: 'handoff_code_invalid',
        error_description: 'client_id or redirect_uri mismatch.'
      }, status: :bad_request
      return
    end

    # Validate application exists
    application = Doorkeeper::Application.find_by(uid: client_id)
    if application.nil?
      render json: {
        error: 'invalid_client',
        error_code: 'mobile_client_not_allowed',
        error_description: 'Unknown or disallowed client_id.'
      }, status: :unauthorized
      return
    end

    # Find the user
    user = User.find_by(id: cached_data[:user_id])
    if user.nil?
      render json: {
        error: 'invalid_grant',
        error_code: 'handoff_code_invalid',
        error_description: 'User not found.'
      }, status: :bad_request
      return
    end

    if user.account.unavailable?
      render json: {
        error: 'access_denied',
        error_code: 'mobile_session_not_allowed',
        error_description: 'Your account is disabled.'
      }, status: :forbidden
      return
    end

    # Create Doorkeeper access token
    scopes = cached_data[:scope].presence || Doorkeeper.config.default_scopes.to_s
    
    access_token = Doorkeeper::AccessToken.create!(
      application_id: application.id,
      resource_owner_id: user.id,
      scopes: scopes,
      expires_in: Doorkeeper.configuration.access_token_expires_in,
      use_refresh_token: Doorkeeper.configuration.refresh_token_enabled?
    )

    # Return success response
    render json: {
      access_token: access_token.token,
      token_type: 'Bearer',
      scope: access_token.scopes.to_s,
      created_at: access_token.created_at.to_i,
      expires_in: access_token.expires_in,
      refresh_token: access_token.refresh_token,
      account: ActiveModelSerializers::SerializableResource.new(
        user.account,
        serializer: REST::CredentialAccountSerializer,
        scope: user,
        scope_name: :current_user
      ).as_json
    }
  end
end
