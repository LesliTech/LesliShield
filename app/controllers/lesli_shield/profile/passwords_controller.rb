module LesliShield
    module Profile
        class PasswordsController < ApplicationController
            PASSWORD_CHANGE_RATE_LIMIT_WINDOW = 15.minutes

            skip_before_action :authorize_request

            rate_limit(
                to: 10,
                within: PASSWORD_CHANGE_RATE_LIMIT_WINDOW,
                by: -> { current_user&.id || request.remote_ip },
                with: :respond_to_password_change_rate_limit,
                only: :update,
                name: "profile-password-update"
            )

            def update
                @active_profile_tab = "security"
                @password = PasswordService
                    .new(current_user)
                    .update(
                        password_params,
                        current_session_id: session[:user_session_id]
                    )
                @user = @password.result

                if @password.successful?
                    bypass_sign_in(@user)
                    record_password_event(
                        operation: "password_change_succeeded",
                        description: "Password changed successfully"
                    )

                    respond_with_lesli(
                        turbo: [
                            stream_notification_success(success_message),
                            stream_redirection(profile_path(tab: "security"))
                        ],
                        json: { message: success_message },
                        redirect: profile_path(tab: "security")
                    )
                else
                    record_password_event(
                        operation: "password_change_failed",
                        description: "Password change failed validation"
                    )

                    respond_with_lesli(
                        turbo: [
                            stream_notification_danger(@password.errors_as_sentence),
                            turbo_stream.replace(
                                "shield-profile-password-form",
                                partial: "lesli_shield/profiles/password-form",
                                locals: { user: @user }
                            )
                        ],
                        json: { errors: @password.errors },
                        html: "lesli_shield/profiles/show",
                        status: :unprocessable_content
                    )
                end
            end

            private

            def password_params
                params.require(:user).permit(
                    :current_password,
                    :password,
                    :password_confirmation
                )
            end

            def success_message
                I18n.t("lesli_shield.profiles.password_updated")
            end

            def record_password_event(operation:, description:)
                log(operation: operation, description: description)
            rescue StandardError => exception
                Rails.error.report(
                    exception,
                    handled: true,
                    context: {
                        controller: self.class.name,
                        operation: operation
                    }
                )
            end

            def respond_to_password_change_rate_limit
                @active_profile_tab = "security"
                @user = current_user
                message = I18n.t(
                    "lesli_shield.profiles.password_too_many_attempts"
                )

                response.set_header(
                    "Retry-After",
                    PASSWORD_CHANGE_RATE_LIMIT_WINDOW.to_i.to_s
                )

                respond_with_lesli(
                    turbo: [
                        stream_notification_danger(message),
                        turbo_stream.replace(
                            "shield-profile-password-form",
                            partial: "lesli_shield/profiles/password-form",
                            locals: { user: @user }
                        )
                    ],
                    json: { error: message },
                    html: "lesli_shield/profiles/show",
                    status: :too_many_requests
                )
            end
        end
    end
end
