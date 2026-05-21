# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Log Out' do
  include RoutingHelper

  def with_oidc_logout_env(overrides = {}, &block)
    ClimateControl.modify(
      {
        OMNIAUTH_ONLY: 'true',
        OIDC_CLIENT_ID: 'yoush-social-web',
        OIDC_IDP_LOGOUT_REDIRECT_URI: 'https://dev.yoush.social.tapofthink.com/auth/sign_out/callback',
        OIDC_ISSUER: 'https://dev.yoush.auth.tapofthink.com/realms/yoush',
        OIDC_END_SESSION_ENDPOINT: nil,
      }.merge(overrides), &block
    )
  end

  describe 'DELETE /auth/sign_out' do
    let(:user) { Fabricate(:user) }

    before do
      sign_in user
    end

    it 'Logs out the user and redirect' do
      delete '/auth/sign_out'

      expect(response).to redirect_to('/auth/sign_in')
    end

    it 'Logs out the user and return a page to redirect to with a JSON request' do
      delete '/auth/sign_out', headers: { 'HTTP_ACCEPT' => 'application/json' }

      expect(response).to have_http_status(200)
      expect(response.media_type).to eq 'application/json'

      expect(response.parsed_body[:redirect_to]).to eq '/auth/sign_in'
    end

    context 'when oidc-only logout is enabled' do
      around do |example|
        with_oidc_logout_env do
          allow(Rails.configuration.x.omniauth).to receive(:oidc_enabled?).and_return(true)
          example.run
        end
      end

      it 'redirects to the provider logout page without signing out locally first' do
        delete '/auth/sign_out'

        expect(response).to redirect_to(
          'https://dev.yoush.auth.tapofthink.com/realms/yoush/protocol/openid-connect/logout?client_id=yoush-social-web&post_logout_redirect_uri=https%3A%2F%2Fdev.yoush.social.tapofthink.com%2Fauth%2Fsign_out%2Fcallback'
        )
      end

      it 'finishes the local sign out from the callback endpoint' do
        get '/auth/sign_out/callback'

        expect(response).to redirect_to('/')
      end
    end
  end
end
