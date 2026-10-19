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

class Users::RegistrationsController < Devise::RegistrationsController
    REGISTRATION_RATE_LIMIT_WINDOW = 1.hour

    before_action :ensure_registration_allowed!, only: %i[new create]

    rate_limit(
        to: 10,
        within: REGISTRATION_RATE_LIMIT_WINDOW,
        by: -> { request.remote_ip },
        with: :respond_to_registration_rate_limit,
        only: :create,
        name: "registration-ip"
    )

    rate_limit(
        to: 3,
        within: REGISTRATION_RATE_LIMIT_WINDOW,
        by: :registration_email_rate_limit_key,
        with: :respond_to_registration_rate_limit,
        only: :create,
        name: "registration-email"
    )

    # Devise owns user construction, validation, persistence, confirmation
    # delivery, password cleanup, and the active/inactive response flow.
    def create
        super do |user|
            record_user_creation_safely(user)
        end
    end

    protected

    # Standalone registrations remain inactive until confirmation creates the
    # account and role. Preserve the existing UX by returning to the form with
    # Devise's success notice instructing the user to check their email.
    def after_inactive_sign_up_path_for(_user)
        new_user_registration_path
    end

    private

    def ensure_registration_allowed!
        return if Lesli.config.security.dig(:allow_registration)

        redirect_to(
            new_user_session_path,
            alert: I18n.t(
                "lesli_shield.devise/registrations.message_registration_not_allowed"
            ),
            status: request.post? ? :see_other : :found
        )
    end

    def registration_email_rate_limit_key
        normalized_email = registration_params[:email].to_s.strip.downcase
        identity = normalized_email.presence || "blank:#{request.remote_ip}"

        OpenSSL::HMAC.hexdigest(
            "SHA256",
            Rails.application.secret_key_base,
            identity
        )
    end

    def registration_params
        params
            .fetch(resource_name, ActionController::Parameters.new)
            .permit(:email)
    end

    def respond_to_registration_rate_limit
        message = I18n.t(
            "lesli_shield.devise/registrations.message_too_many_attempts"
        )

        response.set_header(
            "Retry-After",
            REGISTRATION_RATE_LIMIT_WINDOW.to_i.to_s
        )

        respond_to do |format|
            format.html { render_registration_rate_limit(message) }
            format.json do
                render json: { error: message }, status: :too_many_requests
            end
            format.any { head :too_many_requests }
        end
    end

    def render_registration_rate_limit(message)
        flash.now[:alert] = message
        self.resource = resource_class.new(email: registration_params[:email])
        set_minimum_password_length
        render :new, status: :too_many_requests
    end

    # A standalone signup has no tenant yet, so its durable audit event belongs
    # to the later confirmation transaction. Keep support for pre-associated
    # resources without allowing an optional audit failure to undo registration.
    def record_user_creation_safely(user)
        return unless user.persisted? && user.account.present?

        user.log(
            engine: LesliShield,
            source: self.class.name,
            action: action_name,
            operation: "user_creation_succeeded",
            description: "User created successfully"
        )
    rescue StandardError => exception
        Rails.error.report(
            exception,
            handled: true,
            context: {
                controller: self.class.name,
                operation: "user_creation_succeeded"
            }
        )
    end
end
