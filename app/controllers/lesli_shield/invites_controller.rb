module LesliShield
    class InvitesController < ApplicationController
        before_action :set_invite, only: %i[show resend cancel]
        before_action :set_assignable_roles, only: %i[new create]

        # GET /invites
        def index
            @status_filter = InviteService.status_filter(params[:status])
            invite_service = LesliShield::InviteService.new(current_user, query)
            @invites = respond_with_pagination(invite_service.index(params))
        end

        # GET /invites/1
        def show
        end

        # GET /invites/new
        def new
            @invite = current_account_invites.new
        end

        # POST /invites
        def create
            @invite = invitation_service.create_and_send!(invite_params)

            log(
                subject: @invite,
                operation: "invite.created",
                description: "Invitation created and queued for #{@invite.email}"
            )

            success(I18n.t("lesli_shield.invites.created_successfully"))
            respond_with_lesli(
                turbo: stream_redirection(invite_path(@invite)),
                redirect: invite_path(@invite)
            )
        rescue ActiveRecord::RecordInvalid => exception
            @invite = exception.record
            respond_with_lesli(
                turbo: stream_notification_danger(
                    @invite.errors.full_messages.to_sentence
                ),
                json: { errors: @invite.errors },
                html: "lesli_shield/invites/new",
                status: :unprocessable_content
            )
        end

        # POST /invites/1/resend
        def resend
            @invite = invitation_service.resend!(@invite)

            log(
                subject: @invite,
                operation: "invite.resent",
                description: "Invitation queued for resend"
            )

            success(I18n.t("lesli_shield.invites.resent_successfully"))
            respond_with_lesli(
                turbo: stream_redirection(invite_path(@invite)),
                redirect: invite_path(@invite)
            )
        rescue Invite::InvalidStatusTransition,
            ActiveRecord::RecordInvalid => exception
            respond_with_lesli(
                turbo: stream_notification_danger(error_message(exception)),
                redirect: invite_path(@invite)
            )
        end

        # PATCH /invites/1/cancel
        def cancel
            @invite = invitation_service.cancel!(@invite)

            log(
                subject: @invite,
                operation: "invite.cancelled",
                description: "Invitation cancelled"
            )

            success(I18n.t("lesli_shield.invites.cancelled_successfully"))
            respond_with_lesli(
                turbo: stream_redirection(invite_path(@invite)),
                redirect: invite_path(@invite)
            )
        rescue Invite::InvalidStatusTransition,
            ActiveRecord::RecordInvalid => exception
            respond_with_lesli(
                turbo: stream_notification_danger(error_message(exception)),
                redirect: invite_path(@invite)
            )
        end

        private

        def set_invite
            # Scoping the lookup makes an invitation from another account
            # indistinguishable from a resource that does not exist.
            @invite = current_account_invites.find(params.expect(:id))
        end

        def set_assignable_roles
            @assignable_roles = current_user.account.roles
                .where(active: true)
                .where(permission_level: (..current_user.max_level_permission))
                .order(permission_level: :desc, name: :asc)
        end

        def current_account_invites
            current_user.account.shield.invites
        end

        def invitation_service
            @invitation_service ||= InvitationService.new(current_user)
        end

        def error_message(exception)
            return exception.record.errors.full_messages.to_sentence if
                exception.respond_to?(:record)

            exception.message
        end

        def invite_params
            params.require(:invite).permit(
                :email,
                :full_name,
                :notes,
                :role_id
            )
        end
    end
end
