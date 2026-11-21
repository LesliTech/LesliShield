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

module LesliShield
    module SecurityInterface
        
        def set_privileges(&action)
            if current_user
                current_user.with_privileges(&action)
            else
                action.call
            end
        end

        # Validate user authentication and session status
        def authenticate_request

            # this version Lesli requires to be mounted as root "/"
            # engine_path = Lesli::Engine.routes.find_script_name({})
            engine_path = nil

            # check if the users is logged into the system
            unless user_signed_in?()

                message = "Please Login to view that page!"

                # check if requested url is valid
                if (request.get? && is_navigational_format? && !request.xhr? && !request.fullpath.blank?)

                    # redirect only if the path worth it
                    if request.fullpath != "/"

                        # redirect with requested url, so user will be redirected after login
                        redirect_to("#{engine_path}/login?r=#{request.fullpath}", notice: message) and return

                    end

                end

                # redirect to root route
                redirect_to("#{engine_path}/login", notice: message) and return

            end

            # run aditinal validations only for html requests
            return true unless request.format.html?

            # # get the current user session
            # current_session = current_user.sessions.find_by(id: session[:user_session_id])

            # # check if user has an active session
            # if current_session.equal? nil or !current_session.active?
            #     current_user.log(operation: "system_session_logout", description: "session finished by the system")
            #     sign_out current_user
            #     redirect_to "#{engine_path}/logout" and return
            # end

            # if !current_session.expiration_at.blank? && current_session.expiration_at < Time.current
            #     current_user.log(operation: "system_session_logout", description: "session expired by the system")
            #     sign_out current_user
            #     redirect_to "#{engine_path}/logout" and return
            # end

            # # check password expiration date
            # if current_user.has_expired_password?
            #     unless controller_name == "profiles"
            #         current_user.log(operation: "redirect_due_to_expired_password")
            #         redirect_to "/administration/profile#force-password-reset", notice: I18n.t("core.users/sessions.messages_danger_password_expired")
            #         return
            #     end
            # end

        end

        # Check if current_user has privileges to complete this request
        def authorize_request

            # check if user has access to the requested controller
            # this search is over all the privileges for all the roles of the users
            granted = current_user.has_privileges_for?(params[:controller], params[:action])


            # get the path to which the user is limited to
            limited_path = false# current_user.has_role_limited_to_path?

            # to redirect to the limited path we must check:
            #   limited_path must not to be nil or empty string ("")
            #   limited_path must not to be equal to the current path (to avoid a loop)
            #   request must not to be AJAX
            #   request must be for show or index views
            if  !limited_path.blank? and
                !(limited_path == request.original_fullpath) and
                !(request[:format] == "json") and
                ["show", "index"].include?(params[:action])

                return redirect_to(limited_path)
            end

            # privilege for object not found
            if granted.blank?
                log(
                    :operation => :authorize_request,
                    :description => "Privilege not found for: #{request.path}"
                )
                return respond_with_forbidden({ controller: params[:controller], action: params[:action] })
            end

            unless granted
                log(
                    :operation => :authorize_request,
                    :description => "Privilege not granted for: #{request.path}"
                )
                return respond_with_forbidden({ controller: params[:controller], action: params[:action] })
            end
        end
    end
end
