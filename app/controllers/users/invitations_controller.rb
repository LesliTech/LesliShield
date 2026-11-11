# frozen_string_literal: true

class Users::InvitationsController < Lesli::ApplicationDeviseController
    before_action :load_invitation

    def edit
        @user = Lesli::User.new(email: @invitation.email)
        set_minimum_password_length
    end

    def update
        accepted_user = invitation_service.accept!(
            token: @invitation_token,
            user_attributes: user_params
        )

        redirect_to(
            new_user_session_path,
            notice: I18n.t(
                "lesli_shield.invites.acceptance_success",
                email: accepted_user.email
            ),
            status: :see_other
        )
    rescue ActiveRecord::RecordInvalid => exception
        return render_not_found unless exception.record.is_a?(Lesli::User)

        @user = exception.record
        set_minimum_password_length
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
    end

    private

    def load_invitation
        @invitation_token = params.expect(:invitation_token)
        @invitation = invitation_service.invitation_from_token!(
            @invitation_token
        )

        render_not_found unless @invitation.acceptance_available?
    rescue ActiveSupport::MessageVerifier::InvalidSignature,
        ActiveRecord::RecordNotFound,
        ActionController::ParameterMissing
        render_not_found
    end

    def invitation_service
        @invitation_service ||= LesliShield::InvitationService.new(nil)
    end

    def user_params
        params.require(:user).permit(
            :first_name,
            :last_name,
            :telephone,
            :password,
            :password_confirmation
        )
    end

    def set_minimum_password_length
        @minimum_password_length = Devise.password_length.min
    end

    def render_not_found
        head :not_found
    end
end
