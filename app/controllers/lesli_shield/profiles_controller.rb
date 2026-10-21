module LesliShield
    class ProfilesController < ApplicationController
        PROFILE_FIELDS = %i[
            id
            uid
            alias
            title
            email
            first_name
            last_name
            telephone
        ].freeze

        skip_before_action :authorize_request
        before_action :set_profile

        def show
            respond_with_lesli(json: profile_payload)
        end

        def update
            @profile.update(profile_params)
            @user = @profile.result

            if @profile.successful?
                respond_with_lesli(
                    turbo: stream_notification_success("Profile updated successfully!"),
                    json: profile_payload,
                    redirect: profile_path
                )
            else
                respond_with_lesli(
                    turbo: stream_notification_danger(@profile.errors_as_sentence),
                    json: { errors: @profile.errors },
                    html: :show,
                    status: :unprocessable_content
                )
            end
        end

        private

        def set_profile
            @profile = LesliShield::ProfileService.new(current_user)
            @user = @profile.show
        end

        def profile_params
            params.require(:user).permit(
                :alias,
                :title,
                :email,
                :first_name,
                :last_name,
                :telephone
            )
        end

        def profile_payload
            @user.as_json(only: PROFILE_FIELDS)
        end
    end
end
