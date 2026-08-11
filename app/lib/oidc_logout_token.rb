# frozen_string_literal: true

# An OpenID Connect back-channel logout token, checked against the provider that
# issued it.
#
# Keycloak POSTs one of these to an unauthenticated endpoint whenever a session
# ends anywhere, so every claim is attacker-controlled until the signature says
# otherwise. Almost all of this class is validation; the only thing it produces
# is the subject the provider is telling us to sign out.
class OidcLogoutToken
  # Marks the JWT as a logout token rather than an ID token, which is what stops
  # a captured ID token from being replayed here to sign someone out.
  BACKCHANNEL_LOGOUT_EVENT = 'http://schemas.openid.net/event/backchannel-logout'

  # Asymmetric only. Accepting an HMAC algorithm here would invite the classic
  # confusion attack where the provider's public key is used as a shared secret.
  SIGNING_ALGORITHMS = %i(RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512).freeze

  # How far out of date an issued-at may be: wide enough for clock skew between
  # the provider and us, short enough that a captured token stops working.
  MAX_AGE = 5.minutes

  JWKS_CACHE_KEY = 'oidc:backchannel_logout:jwks'
  JWKS_CACHE_TTL = 12.hours

  class InvalidToken < StandardError; end

  attr_reader :claims

  def self.decode!(raw_token)
    new(raw_token).validate!
  end

  def initialize(raw_token)
    raise InvalidToken, 'missing logout_token' if raw_token.blank?

    @claims = verify_signature(raw_token)
  end

  def validate!
    validate_issuer!
    validate_audience!
    validate_freshness!
    validate_event!
    validate_subject!
    self
  end

  # The OIDC subject. Identity#uid holds exactly this, because OIDC_UID_FIELD is
  # configured as `sub`.
  def subject
    claims['sub']
  end

  # Present, but deliberately not acted on: Yoush signs the user out of every
  # session rather than only the one the provider names. Logged, so an
  # unexpectedly narrow logout can be traced back to a single session.
  def session_id
    claims['sid']
  end

  private

  def verify_signature(raw_token)
    JSON::JWT.decode(raw_token, jwks, SIGNING_ALGORITHMS)
  rescue JSON::JWK::Set::KidNotFound
    # Providers rotate signing keys without announcing it, and a cached key set
    # that predates the rotation is the ordinary reason a good token fails.
    JSON::JWT.decode(raw_token, jwks(force_refresh: true), SIGNING_ALGORITHMS)
  rescue JSON::JWT::Exception => e
    raise InvalidToken, "signature verification failed (#{e.class})"
  end

  def jwks(force_refresh: false)
    Rails.cache.delete(JWKS_CACHE_KEY) if force_refresh

    raw = Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: JWKS_CACHE_TTL) { fetch_jwks.to_json }

    JSON::JWK::Set.new(JSON.parse(raw))
  end

  def fetch_jwks
    document = if jwks_uri.present?
                 OpenIDConnect.http_client.get(jwks_uri).body
               else
                 OpenIDConnect::Discovery::Provider::Config.discover!(issuer).jwks
               end

    JSON::JWK::Set.new(document)
  rescue OpenIDConnect::Discovery::DiscoveryFailed, Faraday::Error => e
    raise InvalidToken, "could not load the provider's signing keys (#{e.class})"
  end

  def validate_issuer!
    raise InvalidToken, 'issuer mismatch' unless issuer.present? && claims['iss'] == issuer
  end

  def validate_audience!
    raise InvalidToken, 'audience mismatch' unless client_id.present? && Array(claims['aud']).include?(client_id)
  end

  def validate_freshness!
    issued_at = claims['iat']
    raise InvalidToken, 'missing iat' if issued_at.blank?
    raise InvalidToken, 'stale token' if Time.zone.at(issued_at) < MAX_AGE.ago

    expires_at = claims['exp']
    raise InvalidToken, 'expired token' if expires_at.present? && Time.zone.at(expires_at) < Time.now.utc
  end

  def validate_event!
    events = claims['events']
    raise InvalidToken, 'not a logout token' unless events.is_a?(Hash) && events.key?(BACKCHANNEL_LOGOUT_EVENT)

    # An ID token carries a nonce and a logout token must not, so its presence
    # means something is being replayed that was never meant for this endpoint.
    raise InvalidToken, 'nonce present' if claims['nonce'].present?
  end

  def validate_subject!
    raise InvalidToken, 'missing sub' if subject.blank?
  end

  def issuer
    ENV.fetch('OIDC_ISSUER', nil)
  end

  def client_id
    ENV.fetch('OIDC_CLIENT_ID', nil)
  end

  def jwks_uri
    ENV.fetch('OIDC_JWKS_URI', nil)
  end
end
