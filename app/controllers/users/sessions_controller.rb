=begin

Lesli

Copyright (c) 2026, Lesli Technologies, S. A.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see http://www.gnu.org/licenses/.

Lesli · Ruby on Rails SaaS Development Framework.

Made with ♥ by LesliTech
Building a better future, one line of code at a time.

@contact  hello@lesli.tech
@website  https://www.lesli.tech
@license  GPLv3 http://www.gnu.org/licenses/gpl-3.0.en.html

// · ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~     ~·~
// · 
=end

require "openssl"

class Users::SessionsController < Devise::SessionsController
    LOGIN_RATE_LIMIT_WINDOW = 15.minutes

    rate_limit(
        to: 20,
        within: LOGIN_RATE_LIMIT_WINDOW,
        by: -> { request.remote_ip },
        with: :respond_to_login_rate_limit,
        only: :create,
        name: "login-ip"
    )

    rate_limit(
        to: 10,
        within: LOGIN_RATE_LIMIT_WINDOW,
        by: :login_email_rate_limit_key,
        with: :respond_to_login_rate_limit,
        only: :create,
        name: "login-email"
    )

    # Devise owns the authentication pipeline and yields only after credentials
    # and active_for_authentication? have been accepted and the web session has
    # been established. LesliShield adds its application session and audit event
    # without reimplementing Devise's create action.
    def create
        super do |user|
            persist_application_session!(user)
            record_successful_login_analytics
        end
    end

    protected

    # Devise calls this method only after a successful authentication. url_from
    # accepts local paths and URLs for the current host while rejecting external
    # and protocol-relative URLs.
    def after_sign_in_path_for(_user)
        url_from(requested_redirect) || configured_after_sign_in_path
    end

    private

    # Devise has already established the web session when its create action
    # yields. If either mandatory write fails, remove that session so the request
    # cannot leave a partially completed login behind.
    def persist_application_session!(user)
        application_session_id = create_application_session_and_audit!(user)
        session[:user_session_id] = application_session_id
    rescue StandardError
        rollback_web_session
        raise
    end

    # The LesliShield session and its single successful-login audit event are
    # committed atomically.
    def create_application_session_and_audit!(user)
        Lesli::User.transaction do
            application_session = LesliShield::UserSessionService
                .new(user)
                .create(request.remote_ip, detected_user_agent)
                .result

            user.log(
                engine: LesliShield,
                source: self.class.name,
                action: action_name,
                operation: "session_creation_succeeded",
                description: "Session creation successful",
                session_id: application_session.id
            )

            application_session.id
        end
    end

    def rollback_web_session
        session.delete(:user_session_id)
        sign_out(resource_name)
    end

    # Request and device records are analytics, not additional authentication
    # audit events.
    def record_successful_login_analytics
        log_requests if respond_to?(:log_requests)
        log_devices if respond_to?(:log_devices)
    end

    def detected_user_agent
        get_user_agent if respond_to?(:get_user_agent)
    end

    def configured_after_sign_in_path
        Lesli.config.shield.dig(:path_after_login) || root_path
    end

    def requested_redirect
        login_request_params[:redirect]
    end

    def login_request_params
        params.fetch(:user, {}).permit(
            :email,
            :password,
            :remember_me,
            :redirect
        )
    end

    def login_email_rate_limit_key
        normalized_email = login_request_params[:email].to_s.strip.downcase
        identity = normalized_email.presence || "blank:#{request.remote_ip}"

        OpenSSL::HMAC.hexdigest(
            "SHA256",
            Rails.application.secret_key_base,
            identity
        )
    end

    def respond_to_login_rate_limit
        message = I18n.t("lesli_shield.devise/sessions.message_too_many_attempts")
        response.set_header("Retry-After", LOGIN_RATE_LIMIT_WINDOW.to_i.to_s)

        respond_to do |format|
            format.html do
                self.resource = resource_class.new(
                    email: login_request_params[:email]
                )

                flash.now[:alert] = message
                render :new, status: :too_many_requests
            end

            format.json do
                render json: { error: message }, status: :too_many_requests
            end

            format.any { head :too_many_requests }
        end
    end
end
