# frozen_string_literal: true

class Users::InvitationsController < Lesli::ApplicationDeviseController
    before_action :protect_invitation_response
    before_action :load_invitation

    def show
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
        unless exception.record.is_a?(Lesli::User)
            return render_invitation_unavailable(
                invitation_failure_reason(exception.record),
                :gone
            )
        end

        @user = exception.record
        set_minimum_password_length
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render :show, status: :unprocessable_content
    end

    private

    def load_invitation
        @invitation_token = params.expect(:invitation_token)
        @invitation = invitation_service.invitation_from_token!(
            @invitation_token
        )
    rescue ActiveRecord::RecordInvalid => exception
        render_invitation_unavailable(
            invitation_failure_reason(exception.record),
            :gone
        )
    rescue ActiveSupport::MessageVerifier::InvalidSignature,
        ActiveRecord::RecordNotFound,
        ActionController::ParameterMissing
        render_invitation_unavailable(:invalid, :not_found)
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

    def protect_invitation_response
        response.set_header("Cache-Control", "no-store")
        response.set_header("Referrer-Policy", "same-origin")
    end

    def invitation_failure_reason(invitation)
        return :used if invitation.accepted? || invitation.accepted_at.present?
        return :cancelled if invitation.cancelled? ||
            invitation.cancelled_at.present?
        return :expired if invitation.expired? ||
            invitation.expires_at&.past?

        :unavailable
    end

    def render_invitation_unavailable(reason, status)
        @invitation_error_title = I18n.t(
            "lesli_shield.invites.acceptance_#{reason}_title"
        )
        @invitation_error_description = I18n.t(
            "lesli_shield.invites.acceptance_#{reason}_description"
        )

        render :unavailable, status: status
    end
end
