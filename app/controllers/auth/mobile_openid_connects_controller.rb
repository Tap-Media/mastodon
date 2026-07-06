# frozen_string_literal: true

class Auth::MobileOpenidConnectsController < ApplicationController
  layout 'auth'

  content_security_policy false

  def new
    client_id = params[:client_id]
    redirect_uri = params[:redirect_uri]
    state = params[:state]
    scope = params[:scope]
    mode = params[:mode] || 'login'

    if client_id.blank? || redirect_uri.blank? || state.blank?
      render plain: 'Missing client_id, redirect_uri, or state parameters.', status: :bad_request
      return
    end

    # Validate client_id and redirect_uri against Doorkeeper applications
    application = Doorkeeper::Application.find_by(uid: client_id)
    if application.nil?
      render plain: 'Invalid client_id.', status: :unauthorized
      return
    end

    # Check redirect_uri is registered
    allowed_uris = application.redirect_uri.split
    unless allowed_uris.include?(redirect_uri)
      render plain: 'Invalid redirect_uri.', status: :bad_request
      return
    end

    # Save to session
    session[:mobile_handoff] = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      state: state,
      scope: scope,
      mode: mode
    }

    # Render template that POSTs to omniauth request phase
  end
end
