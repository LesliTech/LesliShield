# frozen_string_literal: true

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

class Users::RegistrationsController < Devise::RegistrationsController
    before_action :configure_sign_up_params, only: [:create]
    # before_action :configure_account_update_params, only: [:update]

    # GET /resource/sign_up
    # def new
    #   super
    # end

    def create
        begin

            # Check if instance allow multi-account
            if !Lesli.config.security.dig(:allow_registration)
                raise(I18n.t("core.users/registrations.messages_error_registration_not_allowed"))
            end

            # build new user
            user = build_resource(sign_up_params)

            # persist new user
            if user.save
                user.log(engine: LesliShield, source: self.class.name, action: action_name, operation: 'user_creation', description: 'User creation successfully')
                success("Account created, check your email")
            else
                raise(user.errors.full_messages.to_sentence)
            end
        rescue => exception
            #Honeybadger.notify(exception)
            danger(exception.message)
        end
        redirect_to(new_user_registration_path)
    end

    # GET /resource/edit
    # def edit
    #   super
    # end

    # PUT /resource
    # def update
    #   super
    # end

    # DELETE /resource
    # def destroy
    #   super
    # end

    # GET /resource/cancel
    # Forces the session data which is usually expired after sign
    # in to be expired now. This is useful if the user wants to
    # cancel oauth signing in/up in the middle of the process,
    # removing all OAuth session data.
    # def cancel
    #   super
    # end

    protected

    # If you have extra params to permit, append them to the sanitizer.
    # def configure_account_update_params
    #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
    # end

    # If you have extra params to permit, append them to the sanitizer.
    def configure_sign_up_params
        devise_parameter_sanitizer.permit(:sign_up, keys: [
            :email, 
            :password, 
            :password_confirmation
        ])
    end

    # The path used after sign up.
    # def after_sign_up_path_for(resource)
    #   super(resource)
    # end

    # The path used after sign up for inactive accounts.
    # def after_inactive_sign_up_path_for(resource)
    #   super(resource)
    # end

    # def sign_up_params
    #     params.permit(:sign_up, keys: [
    #         :email, 
    #         :password, 
    #         :password_confirmation
    #     ])
    # end

    def sign_up_params
        params.fetch(:user, {}).permit(:email, :password, :password_confirmation)
    end
end
