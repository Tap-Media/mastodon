# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OIDC back-channel logout' do
  subject { post '/auth/sign_out/backchannel', params: { logout_token: logout_token } }

  let(:issuer)    { 'https://auth.example.com/realms/yoush' }
  let(:client_id) { 'yoush-social-web' }
  let(:jwks_uri)  { "#{issuer}/protocol/openid-connect/certs" }

  let(:signing_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:signing_jwk) { JSON::JWK.new(signing_key, kid: 'test-key') }
  let(:published_jwk) { JSON::JWK.new(signing_key.public_key, kid: 'test-key') }

  let(:user) { Fabricate(:user) }
  let(:subject_claim) { 'keycloak-subject-uuid' }
  let(:logout_token) { signed_token }

  def signed_token(claims = {}, key: signing_jwk)
    JSON::JWT.new(
      {
        iss: issuer,
        aud: client_id,
        iat: Time.now.to_i,
        jti: SecureRandom.uuid,
        sub: subject_claim,
        sid: 'keycloak-session-id',
        events: { OidcLogoutToken::BACKCHANNEL_LOGOUT_EVENT => {} },
      }.merge(claims)
    ).sign(key, :RS256).to_s
  end

  def publish_keys(jwks)
    stub_request(:get, jwks_uri).to_return(
      body: { keys: jwks }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  around do |example|
    ClimateControl.modify(
      OIDC_ISSUER: issuer,
      OIDC_CLIENT_ID: client_id,
      OIDC_JWKS_URI: jwks_uri
    ) { example.run }
  end

  before do
    allow(Rails.configuration.x.omniauth).to receive(:oidc_enabled?).and_return(true)
    Rails.cache.clear
    publish_keys([published_jwk])
    Fabricate(:identity, user: user, provider: 'openid_connect', uid: subject_claim)
  end

  context 'with a valid logout token' do
    it 'returns http success' do
      subject

      expect(response).to have_http_status(200)
    end

    it 'ends every session the user has, not only the one the token names' do
      3.times { Fabricate(:session_activation, user: user) }

      expect { subject }
        .to change { user.session_activations.count }.from(3).to(0)
    end

    it 'revokes the access tokens held by connected applications' do
      token = Fabricate(:access_token, resource_owner_id: user.id)

      expect { subject }
        .to change { token.reload.revoked_at }.from(nil).to(be_present)
    end

    it 'leaves other users signed in' do
      other = Fabricate(:user)
      Fabricate(:session_activation, user: other)

      expect { subject }
        .to_not(change { other.session_activations.count })
    end
  end

  context 'when the subject belongs to nobody here' do
    before { Identity.destroy_all }

    it 'returns http success, so the provider stops retrying something we cannot act on' do
      subject

      expect(response).to have_http_status(200)
    end
  end

  context 'when the token is signed by someone else' do
    let(:logout_token) { signed_token({}, key: JSON::JWK.new(OpenSSL::PKey::RSA.generate(2048), kid: 'test-key')) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end

    it 'leaves the sessions alone' do
      Fabricate(:session_activation, user: user)

      expect { subject }
        .to_not(change { user.session_activations.count })
    end
  end

  context 'when an ID token is replayed in place of a logout token' do
    # An ID token carries no logout event and does carry a nonce. Either check
    # alone has to reject it, or any captured login token becomes a way to sign
    # an arbitrary user out.
    let(:logout_token) { signed_token({ events: nil, nonce: 'abc123' }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the token carries a logout event but also a nonce' do
    let(:logout_token) { signed_token({ nonce: 'abc123' }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the token was issued for a different client' do
    let(:logout_token) { signed_token({ aud: 'some-other-client' }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the token was issued by a different provider' do
    let(:logout_token) { signed_token({ iss: 'https://evil.example.com/realms/yoush' }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the token is older than the accepted window' do
    let(:logout_token) { signed_token({ iat: 10.minutes.ago.to_i }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the token has expired' do
    let(:logout_token) { signed_token({ exp: 1.minute.ago.to_i }) }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when no logout token is posted at all' do
    let(:logout_token) { nil }

    it 'returns http bad request' do
      subject

      expect(response).to have_http_status(400)
    end
  end

  context 'when the provider has rotated its signing key' do
    let(:rotated_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:logout_token) { signed_token({}, key: JSON::JWK.new(rotated_key, kid: 'rotated-key')) }

    before do
      # Fill the key cache with the pre-rotation key set, then publish only the
      # new one -- the state a real rotation leaves us in.
      post '/auth/sign_out/backchannel', params: { logout_token: signed_token }
      publish_keys([JSON::JWK.new(rotated_key.public_key, kid: 'rotated-key')])
    end

    it 'refetches the key set and accepts the token' do
      subject

      expect(response).to have_http_status(200)
    end
  end

  context 'when OIDC is disabled' do
    before do
      allow(Rails.configuration.x.omniauth).to receive(:oidc_enabled?).and_return(false)
    end

    it 'returns http not found' do
      subject

      expect(response).to have_http_status(404)
    end
  end
end
