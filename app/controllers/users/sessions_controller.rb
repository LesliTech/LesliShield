=begin

Lesli

Copyright (c) 2025, Lesli Technologies, S. A.

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

    # Creates a new session for the user and allows them access to the platform
    def create

        # Use guarden to check if the users credetials are valid 
        self.resource = warden.authenticate(auth_options)

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

        log = nil 

        # Save a log for the current login attempt 
        log = user.log(
            engine: LesliShield,
            source: self.class.name,
            action: action_name,
            operation: 'session_new',
            description: 'Session creation attempt'
        ) if defined?(LesliAudit)

        # check if user meet requirements to create a new session
        LesliShield::UserValidatorService.new(user).valid? do |valid, failures|

            # if user do not meet requirements to login
            unless valid

                failures_string = failures.join(", ")
                danger(failures_string)
                log.update(description: failures_string) if log
                redirect_to user_session_path(r: sign_in_params[:redirect]) and return
            end
        end

        # create a new session for the user
        current_session = LesliShield::UserSessionService.new(user)
        .create(request.remote_ip, (get_user_agent(false) if log))
        .result

        # make session id globally available
        session[:user_session_id] = current_session[:id]

        # do a user login
        sign_in(resource_name, user)

        # update logs with a successful login
        log.update(
            description: "Session creation successful", 
            session_id: current_session[:id]
        ) if log

        # respond successful and send the path user should go
        # respond_with_successful({ default_path: user.has_role_with_default_path?() })
        # respond_with_successful({ default_path: Lesli.config.path_after_login || "/" })
        redirect_to safe_redirect_path(sign_in_params[:redirect])

        # Save the user_agent for every new session
        log_devices if log
    end

    private 

    def safe_redirect_path redirect_path
        if redirect_path.present?
            uri = URI.parse(redirect_path)
            # Ensures it's a local path
            return redirect_path if uri.relative?  
        end
        Lesli.config.path_after_login || root_path
    rescue URI::InvalidURIError
        # If the URL is invalid, fallback to root
        root_path  
    end

    def sign_in_params
        params.fetch(:user, {}).permit(:email, :password, :redirect)
    end
end
