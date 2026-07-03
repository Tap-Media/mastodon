# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mobile Keycloak SSO Handoff' do
  let!(:application) do
    Doorkeeper::Application.create!(
      name: 'Mobile App',
      redirect_uri: 'youshsocial://auth/callback',
      scopes: 'read write follow push'
    )
  end

  describe 'GET /auth/mobile/openid_connect' do
    context 'with valid parameters' do
      it 'redirects to omniauth login and stores info in session' do
        get '/auth/mobile/openid_connect', params: {
          client_id: application.uid,
          redirect_uri: 'youshsocial://auth/callback',
          state: 'test_state',
          scope: 'read write',
          mode: 'login'
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('sso_form')
        expect(session[:mobile_handoff].symbolize_keys).to eq({
          client_id: application.uid,
          redirect_uri: 'youshsocial://auth/callback',
          state: 'test_state',
          scope: 'read write',
          mode: 'login'
        })
      end
    end

    context 'with missing parameters' do
      it 'returns bad_request' do
        get '/auth/mobile/openid_connect', params: {
          client_id: application.uid
        }
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with invalid redirect_uri' do
      it 'returns bad_request' do
        get '/auth/mobile/openid_connect', params: {
          client_id: application.uid,
          redirect_uri: 'http://malicious-site.com',
          state: 'test_state'
        }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'OmniAuth callback redirect handoff' do
    before do
      # Set up mobile handoff session
      get '/auth/mobile/openid_connect', params: {
        client_id: application.uid,
        redirect_uri: 'youshsocial://auth/callback',
        state: 'test_state',
        scope: 'read write',
        mode: 'login'
      }

      mock_omniauth(:openid_connect, {
        provider: 'openid_connect',
        uid: '123',
        extra: {
          raw_info: {
            preferred_username: 'yoush_user',
          },
        },
        info: {
          verified: 'true',
          email: 'user@host.example',
        },
      })
    end

    it 'redirects to mobile app callback with one_time_code and state' do
      expect { post '/auth/auth/openid_connect/callback' }
        .to change(User, :count).by(1)

      expect(response).to have_http_status(:found)
      redirect_uri = URI.parse(response.location)
      expect(redirect_uri.scheme).to eq('youshsocial')
      expect(redirect_uri.host).to eq('auth')
      expect(redirect_uri.path).to eq('/callback')

      query = URI.decode_www_form(redirect_uri.query).to_h
      expect(query['state']).to eq('test_state')
      expect(query['one_time_code']).to be_present

      # Verify cache storage
      cached = Rails.cache.read("mobile_handoff:#{query['one_time_code']}")
      expect(cached).to be_present
      expect(cached[:user_id]).to eq(User.last.id)
    end
  end

  describe 'POST /api/v1/mobile/auth/exchange' do
    let(:user) { Fabricate(:user) }
    let(:one_time_code) { 'test_code' }

    before do
      Rails.cache.write("mobile_handoff:#{one_time_code}", {
        user_id: user.id,
        client_id: application.uid,
        redirect_uri: 'youshsocial://auth/callback',
        scope: 'read write'
      })
    end

    context 'with valid parameters' do
      it 'exchanges one-time code for Doorkeeper access token' do
        post '/api/v1/mobile/auth/exchange', params: {
          one_time_code: one_time_code,
          client_id: application.uid,
          redirect_uri: 'youshsocial://auth/callback'
        }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['access_token']).to be_present
        expect(json['token_type']).to eq('Bearer')
        expect(json['scope']).to eq('read write')
        expect(json['account']).to be_present
        expect(json['account']['id']).to eq(user.account.id.to_s)
        
        # Verify single-use
        expect(Rails.cache.read("mobile_handoff:#{one_time_code}")).to be_nil
      end
    end

    context 'with invalid or expired code' do
      it 'returns bad_request' do
        post '/api/v1/mobile/auth/exchange', params: {
          one_time_code: 'invalid_code',
          client_id: application.uid,
          redirect_uri: 'youshsocial://auth/callback'
        }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('invalid_grant')
      end
    end
  end
end
