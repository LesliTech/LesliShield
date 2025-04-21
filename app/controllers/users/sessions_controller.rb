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

#require "uri"

class Users::SessionsController < Devise::SessionsController

    # Creates a new session for the user and allows them access to the platform
    def create

        # search for a existing user 
        user = ::Lesli::User.find_for_database_authentication(email: sign_in_params[:email])        

        # respond with a no valid credentials generic error if not valid user found
        unless user
            danger(I18n.t("lesli.users/sessions.message_invalid_credentials"))
            redirect_to user_session_path(:r => sign_in_params[:redirect]) and return 
        end

        # save a invalid credentials log for the requested user
        activity = user.activities.new({ title: "session_create", description:"atempt" })

        # check password validation
        unless user.valid_password?(sign_in_params[:password])

            # save a invalid credentials log for the requested user
            activity.update(description: "invalid_credentials")

            # respond with a no valid credentials generic error if not valid user found
            danger(I18n.t("lesli.users/sessions.message_invalid_credentials"))
            redirect_to user_session_path(:r => sign_in_params[:redirect]) and return 
        end

        # check if user meet requirements to create a new session
        Lesli::UsersValidator.new(user).valid? do |valid, failures|

            # if user do not meet requirements to login
            unless valid

                activity.update(description: failures.join(", "))

                danger(failures.join(", "))
                redirect_to user_session_path(:r => sign_in_params[:redirect]) and return 
            end
        end


        # remember the user (not enabled by default)
        # remember_me(user) if sign_in_params[:remember_me] == '1'


        # create a new session for the user
        current_session = Lesli::User::SessionService.new(user)
        .create(get_user_agent(false), request.remote_ip)
        .result

        # make session id globally available
        session[:user_session_id] = current_session[:id]

        # create a new multi factor authentication service instance for the current user 
        #mfa_service = User::MfaService.new(user, log)

        # generate a new mfa for the current session (if enabled)
        #mfa_service.generate do |success|
            # mfa was successfully generated, return the user to the mfa page
            # return respond_with_successful({ default_path: "mfa" }) if success
        #end 

        # do a user login
        sign_in(:user, user)

        # create a log for login atempts
        activity.update({ 
            title: "session_create", 
            description: "successful", 
            session_id: current_session[:id] 
        })

        # respond successful and send the path user should go
        #respond_with_successful({ default_path: user.has_role_with_default_path?() })
        #respond_with_successful({ default_path: Lesli.config.path_after_login || "/" })
        redirect_to(safe_redirect_path(sign_in_params[:redirect]))
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
