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

class Users::SessionsController < Devise::SessionsController

    # Creates a new session for the user and allows them access to the platform.
    #
    # Devise provides extension points such as Warden hooks and a custom FailureApp
    # to modify the authentication flow. However, in this case we need full and
    # explicit control over each step of the login process, including validation,
    # logging, session creation, and redirection.
    #
    # For that reason, the default Devise session logic is intentionally overridden
    # and reimplemented here. While this approach is less conventional and may
    # introduce compatibility risks with future Devise releases, it provides a
    # predictable and fully controlled authentication pipeline, which is important
    # for the needs of this framework.
    #
    # This trade-off is accepted as part of the framework’s lifecycle: any
    # incompatibilities introduced by Devise updates will be addressed and
    # maintained as needed.
    def create

        # Validate credentials without publishing a Warden session. The user is
        # signed in only after account validation and session persistence pass.
        self.resource = warden.authenticate(auth_options.merge(store: false))

        # respond with a no valid credentials generic error if warden
        # cannot validate the user
        unless resource
            danger(I18n.t("lesli_shield.devise/sessions.message_not_valid_credentials"))
            redirect_to user_session_path(r: sign_in_params[:redirect]) and return
        end

        user = resource

        # check if user has a valid account
        unless user.account
            danger(I18n.t("lesli_shield.devise/sessions.message_not_confirmed_account"))
            redirect_to user_session_path(r: sign_in_params[:redirect]) and return
        end

        # check if user meet requirements to create a new session
        validator = LesliShield::UserValidatorService.new(user).validate

        # if user do not meet requirements to login
        unless validator.valid?
            failures_string = validator.errors_as_sentence

            user.log(
                engine: LesliShield,
                source: self.class.name,
                action: action_name,
                operation: "session_creation_failed",
                description: failures_string
            )

            danger(failures_string)
            redirect_to user_session_path(r: sign_in_params[:redirect]) and return
        end

        # Persist the session and its success event atomically. The success
        # event is written only after Devise has completed the sign-in.
        user_agent = get_user_agent if respond_to?(:get_user_agent)

        create_authenticated_session!(user, user_agent)

        # Request analytics and device statistics are intentionally separate:
        # devices represent successful logins, not every authenticated request.
        log_requests if respond_to?(:log_requests)
        log_devices if respond_to?(:log_devices)

        # respond successful and send the path user should go
        # respond_with_successful({ default_path: user.has_role_with_default_path?() })
        # respond_with_successful({ default_path: Lesli.config.path_after_login || "/" })
        redirect_to safe_redirect_path(sign_in_params[:redirect])
    end

    private

    def create_authenticated_session!(user, user_agent)
        signed_in = false

        Lesli::User.transaction do
            created_session = LesliShield::UserSessionService.new(user)
            .create(request.remote_ip, user_agent)
            .result

            # Complete the Devise authentication before recording success.
            sign_in(resource_name, user)
            signed_in = true

            # Publish the application session after Devise renews its session.
            session[:user_session_id] = created_session[:id]

            user.log(
                engine: LesliShield,
                source: self.class.name,
                action: action_name,
                operation: "session_creation_succeeded",
                description: "Session creation successful",
                session_id: created_session[:id]
            )

            created_session
        end
    rescue StandardError
        # Do not leave a Warden session active when persistence or mandatory
        # audit logging fails after sign-in.
        session.delete(:user_session_id)
        sign_out(resource_name) if signed_in
        raise
    end

    def safe_redirect_path(redirect_path)
        url_from(redirect_path) || default_after_sign_in_path
    end

    def default_after_sign_in_path
        Lesli.config.shield.dig(:path_after_login) || root_path
    end

    def sign_in_params
        params.fetch(:user, {}).permit(:email, :password, :redirect)
    end
end
