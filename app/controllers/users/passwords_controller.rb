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
        Lesli::User.transaction do
            self.resource = resource_class.send_reset_password_instructions(resource_params)

            user = self.resource

            if successfully_sent?(resource)

                record_activity(
                    user,
                    operation: "password_reset_instructions_sent",
                    description: "Reset password instructions sent"
                )

                success(I18n.t("core.users/passwords.messages_success"))
                redirect_to(new_user_password_path)
            else
                #respond_with(resource)
                danger("Error sending reset password instructions")
                redirect_to(new_user_password_path)
            end
        end
    end

    def update
        Lesli::User.transaction do
            super do |user|

                record_activity(
                    user,
                    operation: "password_update_attempted",
                    description: "Password update attempt"
                )

                # check if password update was ok
                if user.errors.empty?

                    # reset password expiration due the user just updated his password
                    if user.has_expired_password?
                        user.update!(password_expiration_at: nil)
                    end

                    record_activity(
                        user,
                        operation: "password_update_succeeded",
                        description: "Password update successful"
                    )
                else
                    failure_description = resource.errors.full_messages.to_sentence
                    danger(failure_description)
                    record_activity(
                        user,
                        operation: "password_update_failed",
                        description: failure_description
                    )
                end
            end
        end
    end

    private

    # Invalid or unknown reset tokens can produce a resource without a tenant.
    # Those attempts cannot be written to tenant-scoped Audit tables.
    def record_activity(user, operation:, description:)
        return unless user&.account

        user.log(
            engine: LesliShield,
            source: self.class.name,
            action: action_name,
            operation: operation,
            description: description
        )
    end
end
