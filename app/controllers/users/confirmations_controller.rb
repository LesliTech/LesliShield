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

class Users::ConfirmationsController < Devise::ConfirmationsController
    CONFIRMATION_RATE_LIMIT_WINDOW = 1.hour

    rate_limit(
        to: 10,
        within: CONFIRMATION_RATE_LIMIT_WINDOW,
        by: -> { request.remote_ip },
        with: :respond_to_confirmation_rate_limit,
        only: :create,
        name: "confirmation-request-ip"
    )

    rate_limit(
        to: 3,
        within: CONFIRMATION_RATE_LIMIT_WINDOW,
        by: :confirmation_email_rate_limit_key,
        with: :respond_to_confirmation_rate_limit,
        only: :create,
        name: "confirmation-request-email"
    )

    before_action :protect_confirmation_token, only: :show

    # Devise validates and consumes the raw token. Account provisioning and the
    # successful audit event share the same transaction so a partial account can
    # never be left behind and a provisioning failure leaves the token reusable.
    def show
        self.resource = confirm_user_and_provision_account

        if resource.errors.empty?
            send_welcome_email_safely(resource)
            set_flash_message!(:notice, :confirmed)
            respond_with_navigational(resource) do
                redirect_to after_confirmation_path_for(resource_name, resource)
            end
        else
            respond_with_navigational(
                resource.errors,
                status: :unprocessable_content
            ) do
                render :new, status: :unprocessable_content
            end
        end
    end

    protected

    # Keep the user on the resend page so Devise's generic paranoid-mode notice
    # is visible without disclosing whether the email exists or is confirmed.
    def after_resending_confirmation_instructions_path_for(_resource_name)
        new_user_confirmation_path
    end

    private

    def confirm_user_and_provision_account
        confirmed_user = nil

        resource_class.transaction do
            confirmed_user = resource_class.confirm_by_token(
                params[:confirmation_token]
            )

            if confirmed_user.errors.empty?
                LesliShield::UserRegistrationService
                    .new(confirmed_user)
                    .provision_account!

                confirmed_user.update!(confirmation_token: nil)
                record_successful_confirmation!(confirmed_user)
            end
        end

        confirmed_user
    rescue StandardError => exception
        Rails.error.report(
            exception,
            handled: true,
            context: {
                controller: self.class.name,
                operation: "user_confirmation_succeeded"
            }
        )

        confirmation_failure_resource(confirmed_user)
    end

    def confirmation_failure_resource(user)
        failed_resource = if user&.persisted?
            resource_class.find_by(id: user.id)
        end

        failed_resource ||= resource_class.new
        failed_resource.errors.add(
            :base,
            I18n.t(
                "lesli_shield.devise/confirmations.message_confirmation_failed"
            )
        )
        failed_resource
    end

    def record_successful_confirmation!(user)
        user.log(
            engine: LesliShield,
            source: self.class.name,
            action: action_name,
            operation: "user_confirmation_succeeded",
            description: "User confirmed successfully"
        )
    end

    def send_welcome_email_safely(user)
        LesliShield::DeviseMailer.welcome(user).deliver_later
    rescue StandardError => exception
        Rails.error.report(
            exception,
            handled: true,
            context: {
                controller: self.class.name,
                operation: "welcome_email_delivery"
            }
        )
    end

    def confirmation_email_rate_limit_key
        normalized_email = confirmation_request_params[:email]
            .to_s
            .strip
            .downcase
        identity = normalized_email.presence || "blank:#{request.remote_ip}"

        OpenSSL::HMAC.hexdigest(
            "SHA256",
            Rails.application.secret_key_base,
            identity
        )
    end

    def confirmation_request_params
        params
            .fetch(resource_name, ActionController::Parameters.new)
            .permit(:email)
    end

    def respond_to_confirmation_rate_limit
        message = I18n.t(
            "lesli_shield.devise/confirmations.message_too_many_attempts"
        )

        response.set_header(
            "Retry-After",
            CONFIRMATION_RATE_LIMIT_WINDOW.to_i.to_s
        )

        respond_to do |format|
            format.html { render_confirmation_rate_limit(message) }
            format.json do
                render json: { error: message }, status: :too_many_requests
            end
            format.any { head :too_many_requests }
        end
    end

    def render_confirmation_rate_limit(message)
        flash.now[:alert] = message
        self.resource = resource_class.new(
            email: confirmation_request_params[:email]
        )
        render :new, status: :too_many_requests
    end

    def protect_confirmation_token
        # Prevent the token in the query string from being sent to third-party
        # origins while keeping a valid Origin for the resend form rendered when
        # Devise rejects an invalid or expired token.
        response.set_header("Referrer-Policy", "same-origin")
        response.set_header("Cache-Control", "no-store")
    end
end
