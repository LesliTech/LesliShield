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
    class DeviseMailer < Lesli::ApplicationLesliMailer

        # Sends an email with instructions to allow the user reset the password
        def reset_password_instructions(user, token, opts = {})

            # defaults for new accounts/users
            email_template = "devise/reset_password_instructions"
            email_subject = I18n.t("core.users/confirmations.mailer_email_verification")

            # email parameters
            params = {
                url: build_url("/password/edit", { reset_password_token: token}),
                full_name: user.full_name
            }

            # send email
            email(
                params,
                to: user.email, 
                subject: email_subject,
                template_name: email_template
            )
        end 

        # Sends an email to allow the user confirm the email address
        def confirmation_instructions(user, token, opts = {})

            # defaults for new accounts/users
            email_template = "devise/confirmation_instructions"
            email_subject = I18n.t("core.users/confirmations.mailer_email_verification")

            # # custom email and subject if user is changin his email address
            # if !record.unconfirmed_email.blank?
            #     email_template = "update_email_confirmation_instructions"
            #     email_subject = I18n.t("core.users/confirmations.mailer_confirmation_instructions_subject")
            # end

            # Depending on wheter there is a new user or they are changing their email, 
            # one or another field will be used
            email_recipient = user.unconfirmed_email || user.email

            # email parameters
            params = {
                url: build_url("/confirmation", { confirmation_token: token})
            }

            # send email
            email(
                params,
                to: email_recipient, 
                subject: email_subject,
                template_name: email_template
            )
        end

        def welcome(user)
            email_recipient = user.unconfirmed_email || user.email
            email(
                { :user => user },
                to: email_recipient, 
                subject: "test",
                template_name: "devise/welcome"
            )
        end
    end
end
