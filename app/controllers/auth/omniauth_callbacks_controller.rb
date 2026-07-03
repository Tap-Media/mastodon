# frozen_string_literal: true

class Auth::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :check_self_destruct!
  skip_before_action :verify_authenticity_token

  def self.provides_callback_for(provider)
    define_method provider do
      @provider = provider
      @user = User.find_for_omniauth(request.env['omniauth.auth'], current_user)

      if @user.persisted?
        record_login_activity
        
        if session[:mobile_handoff].present?
          handoff_data = session.delete(:mobile_handoff).symbolize_keys
          one_time_code = SecureRandom.hex(16)
          
          Rails.cache.write("mobile_handoff:#{one_time_code}", {
            user_id: @user.id,
            client_id: handoff_data[:client_id],
            redirect_uri: handoff_data[:redirect_uri],
            scope: handoff_data[:scope]
          }, expires_in: 2.minutes)
          
          begin
            uri = URI.parse(handoff_data[:redirect_uri])
            new_query = URI.decode_www_form(uri.query || '') << ['one_time_code', one_time_code] << ['state', handoff_data[:state]]
            uri.query = URI.encode_www_form(new_query)
            redirect_to uri.to_s, allow_other_host: true
          rescue => e
            Rails.logger.error "Mobile redirect failed: #{e.message}"
            redirect_to root_path, alert: "Failed to redirect to mobile app: #{e.message}"
          end
          return
        end

        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: label_for_provider) if is_navigational_format?
      else
        session["devise.#{provider}_data"] = request.env['omniauth.auth']
        redirect_to new_user_registration_url
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "OmniAuth account creation failed for #{provider}: #{e.record.class} #{e.record.errors.full_messages.join(', ')}"
      )
      flash[:alert] = I18n.t('devise.failure.omniauth_user_creation_failure') if is_navigational_format?
      redirect_to new_user_session_url
    end
  end

  Devise.omniauth_configs.each_key do |provider|
    provides_callback_for provider
  end

  def failure
    if session[:mobile_handoff].present?
      handoff_data = session.delete(:mobile_handoff).symbolize_keys
      begin
        uri = URI.parse(handoff_data[:redirect_uri])
        new_query = URI.decode_www_form(uri.query || '') << ['error', 'access_denied'] << ['error_code', 'user_cancelled'] << ['state', handoff_data[:state]]
        uri.query = URI.encode_www_form(new_query)
        redirect_to uri.to_s, allow_other_host: true
      rescue => e
        redirect_to root_path, alert: "Auth failed: #{e.message}"
      end
      return
    end
    super
  end

  def after_sign_in_path_for(resource)
    if resource.email_present?
      stored_location_for(resource) || root_path
    else
      auth_setup_path(missing_email: '1')
    end
  end

  private

  def record_login_activity
    @user.login_activities.create(
      success: true,
      authentication_method: :omniauth,
      provider: @provider,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def label_for_provider
    provider_display_name || configured_provider_name
  end

  def provider_display_name
    Devise.omniauth_configs[@provider]&.strategy&.display_name.presence
  end

  def configured_provider_name
    I18n.t("auth.providers.#{@provider}", default: @provider.to_s.chomp('_oauth2').capitalize)
  end
end
