# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController

    # Sends an email with a token, so the user can reset their password
    def create
        begin

            if params[:user].blank?
                #Account::Activity.log("core", "/password/create", "password_creation_failed", "no_valid_email")
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            if params[:user][:email].blank?
                #Account::Activity.log("core", "/password/create", "password_creation_failed", "no_valid_email")
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            user = Lesli::User.find_by(:email => params[:user][:email])

            if user.blank?
                # Account::Activity.log("core", "/password/create", "password_creation_failed", "no_valid_email", {
                #     email: (params[:user][:email] || "")
                # })
                raise(I18n.t("core.shared.messages_warning_user_not_found"))
            end

            unless user.active
                user.activities.create({title: "password_creation_failed", description: "user_not_active"})
                # Account::Activity.log("core", "/password/create", "password_creation_failed", "user_not_active")
                raise(I18n.t("core.users/passwords.messages_danger_inactive_user"))
            end

            token = user.generate_password_reset_token

            user.activities.create({ title: "password_create", description: "Password reset instructions sent" })

            Lesli::DeviseMailer.reset_password_instructions(user, token).deliver_now
            success(I18n.t("core.users/passwords.messages_success"))
            redirect_to(new_user_password_path)
        rescue => exception
            #Honeybadger.notify(exception)
            danger(exception.message)
            redirect_to(new_user_password_path)
        end
    end

    def update
        super do |resource|

            logs = resource.activities.new({ title: "password_reset", description:"atempt" })

            # check if password update was ok
            if resource.errors.empty?

                # reset password expiration due the user just updated his password
                if resource.has_expired_password?
                    resource.update(password_expiration_at: nil)
                end

                logs.update({ description: "successful" })
            else
                logs.update({ description: resource.errors.full_messages.to_sentence })
            end
        end
    end
end
