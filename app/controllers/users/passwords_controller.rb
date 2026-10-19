# frozen_string_literal: true

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

class Users::PasswordsController < Devise::PasswordsController

    PASSWORD_RESET_RATE_LIMIT_WINDOW = 15.minutes

    rate_limit(
        to: 20,
        within: PASSWORD_RESET_RATE_LIMIT_WINDOW,
        by: -> { request.remote_ip },
        with: :respond_to_password_reset_rate_limit,
        only: :create,
        name: "password-reset-request-ip"
    )

    rate_limit(
        to: 5,
        within: PASSWORD_RESET_RATE_LIMIT_WINDOW,
        by: :password_reset_email_rate_limit_key,
        with: :respond_to_password_reset_rate_limit,
        only: :create,
        name: "password-reset-request-email"
    )

    rate_limit(
        to: 20,
        within: PASSWORD_RESET_RATE_LIMIT_WINDOW,
        by: -> { request.remote_ip },
        with: :respond_to_password_reset_rate_limit,
        only: :update,
        name: "password-reset-update-ip"
    )

    before_action :protect_password_reset_token, only: %i[edit update]

    # Sends an email with a token, so the user can reset their password
    def create
        super do |user|
            record_activity_safely(
                user,
                operation: "password_reset_requested",
                description: "Password reset requested"
            )
        end
    end

    def update
        password_reset_succeeded = false

        super do |user|
            password_reset_succeeded = user.errors.empty?

            if password_reset_succeeded && user.has_expired_password?
                user.update!(password_expiration_at: nil)
            end
        end

        if password_reset_succeeded
            complete_successful_password_reset!(resource)
        else
            record_activity_safely(
                resource,
                operation: "password_reset_failed",
                description: "Password reset failed validation"
            )
        end
    end

    protected

    # Preserve the current UX: after requesting a reset, show the same page with
    # Devise's generic paranoid-mode confirmation instead of revealing whether
    # the submitted email belongs to an account.
    def after_sending_reset_password_instructions_path_for(_resource_name)
        new_user_password_path
    end

    # Devise resets the password even when the account cannot authenticate. Only
    # create a web session when the user also passes LesliShield's account, role,
    # confirmation, and lock checks.
    def sign_in_after_reset_password?
        super && resource.active_for_authentication?
    end

    private

    def complete_successful_password_reset!(user)
        unless user_signed_in?
            record_activity_safely(
                user,
                operation: "password_reset_succeeded",
                description: "Password reset successful"
            )
            return
        end

        session[:user_session_id] = create_application_session_and_audit!(user)
        record_successful_password_reset_analytics
    rescue StandardError
        rollback_web_session
        raise
    end

    # The password has already been committed by Devise at this point. This
    # transaction makes the application session and its single audit event
    # atomic without wrapping Devise's sign-in or response handling.
    def create_application_session_and_audit!(user)
        resource_class.transaction do
            application_session = LesliShield::UserSessionService
                .new(user)
                .create(
                    request.remote_ip,
                    detected_user_agent
                )
                .result

            record_activity(
                user,
                operation: "password_reset_succeeded",
                description: "Password reset successful",
                session_id: application_session.id
            )

            application_session.id
        end
    end

    def rollback_web_session
        session.delete(:user_session_id)
        sign_out(resource_name)
    end

    def record_successful_password_reset_analytics
        log_requests if respond_to?(:log_requests)
        log_devices if respond_to?(:log_devices)
    end

    def detected_user_agent
        get_user_agent if respond_to?(:get_user_agent)
    end

    def password_reset_email_rate_limit_key
        normalized_email = password_reset_request_params[:email].to_s.strip.downcase
        identity = normalized_email.presence || "blank:#{request.remote_ip}"

        OpenSSL::HMAC.hexdigest(
            "SHA256",
            Rails.application.secret_key_base,
            identity
        )
    end

    def password_reset_request_params
        params.fetch(resource_name, {}).permit(:email)
    end

    def respond_to_password_reset_rate_limit
        message = I18n.t(
            "lesli_shield.devise/passwords.message_too_many_attempts"
        )

        response.set_header(
            "Retry-After",
            PASSWORD_RESET_RATE_LIMIT_WINDOW.to_i.to_s
        )

        respond_to do |format|
            format.html { render_password_reset_rate_limit(message) }
            format.json do
                render json: { error: message }, status: :too_many_requests
            end
            format.any { head :too_many_requests }
        end
    end

    def render_password_reset_rate_limit(message)
        flash.now[:alert] = message

        if action_name == "update"
            self.resource = resource_class.new(
                reset_password_token: resource_params[:reset_password_token]
            )
            set_minimum_password_length
            render :edit, status: :too_many_requests
        else
            self.resource = resource_class.new(
                email: password_reset_request_params[:email]
            )
            render :new, status: :too_many_requests
        end
    end

    def protect_password_reset_token
        # `no-referrer` makes some browsers submit the form with `Origin: null`,
        # which Rails correctly rejects when origin-based CSRF protection is
        # enabled. `same-origin` keeps the reset token away from third-party
        # origins while preserving a verifiable origin for the form submission.
        response.set_header("Referrer-Policy", "same-origin")
        response.set_header("Cache-Control", "no-store")
    end

    def record_activity_safely(user, operation:, description:)
        record_activity(
            user,
            operation: operation,
            description: description
        )
    rescue StandardError => exception
        Rails.error.report(
            exception,
            handled: true,
            context: {
                controller: self.class.name,
                operation: operation
            }
        )
    end

    # Invalid or unknown reset tokens can produce a resource without a tenant.
    # Those attempts cannot be written to tenant-scoped Audit tables.
    def record_activity(user, operation:, description:, session_id: nil)
        return unless user&.account

        user.log(
            engine: LesliShield,
            source: self.class.name,
            action: action_name,
            operation: operation,
            description: description,
            session_id: session_id
        )
    end
end
