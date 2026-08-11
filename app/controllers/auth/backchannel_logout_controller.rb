# frozen_string_literal: true

# Receives OpenID Connect back-channel logout notifications from Keycloak.
#
# Keycloak is the single source of truth for whether a Yoush user is signed in,
# and it tells every client when that changes. Signing out anywhere signs the
# user out everywhere, so a notification about one session ends all of this
# user's sessions here rather than the single one the token names.
#
# Server-to-server and unauthenticated by design: the signature on the logout
# token is the only thing that authorises it, so this deliberately skips the
# session, CSRF, and locale machinery that ApplicationController brings.
class Auth::BackchannelLogoutController < ActionController::Base # rubocop:disable Rails/ApplicationController
  OIDC_PROVIDER = 'openid_connect'

  # Keycloak posts this from its own server and has no CSRF token to offer.
  # `config.load_defaults 8.1` turns forgery protection on for every
  # ActionController::Base, so it has to come off explicitly here.
  skip_forgery_protection

  before_action :require_oidc_enabled!
  before_action :set_cache_headers

  def create
    token = OidcLogoutToken.decode!(params[:logout_token])
    sign_out_everywhere(token)

    # The provider retries on failure, so a subject we have never seen still
    # counts as done -- there is nothing left to sign out.
    head 200
  rescue OidcLogoutToken::InvalidToken => e
    Rails.logger.warn { "Rejected back-channel logout: #{e.message}" }
    render json: { error: 'invalid_request', error_description: e.message }, status: 400
  end

  private

  def sign_out_everywhere(token)
    identity = Identity.find_by(provider: OIDC_PROVIDER, uid: token.subject)

    if identity.nil?
      Rails.logger.info { "Back-channel logout for an unknown subject (sid #{token.session_id.presence || 'none'})" }
      return
    end

    user = identity.user
    return if user.nil?

    # Browser sessions first, then everything holding an access token: OAuth
    # applications, the streaming connections they own, and Web Push.
    user.session_activations.destroy_all
    user.revoke_access!

    Rails.logger.info { "Signed out user #{user.id} everywhere (sid #{token.session_id.presence || 'none'})" }
  end

  def require_oidc_enabled!
    head 404 unless Rails.configuration.x.omniauth.oidc_enabled?
  end

  # Nothing here should ever be cached by anything in front of us.
  def set_cache_headers
    response.headers['Cache-Control'] = 'no-store'
  end
end
