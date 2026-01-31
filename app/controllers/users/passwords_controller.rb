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

    # Sends an email with a token, so the user can reset their password
    def create
        begin

            if params[:user].blank?
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            if params[:user][:email].blank?
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            user = Lesli::User.find_by(:email => params[:user][:email])

            if user.blank?
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            log = user.log(:engine => LesliShield, source: self.class.name, :action => action_name, :operation => 'password_reset', :description => 'Reset password attempt')

            unless user.active
                log.update(:description => 'User is not able to reset password due is not active')
                raise(I18n.t("core.users/passwords.messages_danger_inactive_user"))
            end

            token = user.generate_password_reset_token

            log.update(:description => 'Reset password instructions sent')

            ::LesliShield::DeviseMailer.reset_password_instructions(user, token).deliver_now
            success(I18n.t("core.users/passwords.messages_success"))
            redirect_to(new_user_password_path)
        rescue => exception
            #Honeybadger.notify(exception)
            danger(exception.message)
            redirect_to(new_user_password_path)
        end
    end

    def update
        super do |user|

            logs = user.log(engine: LesliShield, source: self.class.name, action: action_name, operation: 'password_update', description:"Password update attempt")

            # check if password update was ok
            if user.errors.empty?

                # reset password expiration due the user just updated his password
                if user.has_expired_password?
                    user.update(password_expiration_at: nil)
                end

                logs.update(description: "Password update successful")
            else
                danger(user.errors.full_messages.to_sentence)
                logs.update(description: resource.errors.full_messages.to_sentence)
            end
        end
    end
end
