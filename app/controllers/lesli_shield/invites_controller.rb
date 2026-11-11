module LesliShield
    class InvitesController < ApplicationController
        before_action :set_invite, only: %i[show update resend cancel]
        before_action :set_assignable_roles, only: %i[new show create update]

        # GET /invites
        def index
            @invites = respond_with_pagination(LesliShield::InviteService.new(current_user, query).index(params))
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

            success("Invite was successfully created and queued for delivery.")
            respond_with_lesli(
                turbo: stream_redirection(invite_path(@invite))
            )
        rescue ActiveRecord::RecordInvalid => exception
            @invite = exception.record
            respond_with_lesli(
                turbo: stream_notification_danger(
                    @invite.errors.full_messages.to_sentence
                )
            )
        end

        # PATCH/PUT /invites/1
        def update
            if @invite.update(invite_attributes)
                log(
                    subject: @invite,
                    description: "Invitation updated successfully"
                )
                respond_with_lesli(
                    :turbo => stream_notification_success("Invite was successfully updated.")
                ) 
            else
                respond_with_lesli(
                    :turbo => stream_notification_danger(@invite.errors.full_messages.to_sentence)
                ) 
            end
        end

        # POST /invites/1/resend
        def resend
            @invite = invitation_service.resend!(@invite)

            log(
                subject: @invite,
                operation: "invite.resent",
                description: "Invitation queued for resend"
            )

            respond_with_lesli(
                turbo: stream_notification_success(
                    "Invite was successfully queued for delivery."
                )
            )
        rescue Invite::InvalidStatusTransition,
            ActiveRecord::RecordInvalid => exception
            respond_with_lesli(
                turbo: stream_notification_danger(error_message(exception))
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

            respond_with_lesli(
                turbo: stream_notification_success(
                    "Invite was successfully cancelled."
                )
            )
        rescue Invite::InvalidStatusTransition,
            ActiveRecord::RecordInvalid => exception
            respond_with_lesli(
                turbo: stream_notification_danger(error_message(exception))
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

        def invite_attributes
            attributes = invite_params.to_h.symbolize_keys
            return attributes unless attributes.key?(:role_id)

            role_id = attributes.delete(:role_id)
            attributes[:role] = role_id.present? ? assignable_role!(role_id) : nil
            attributes
        end

        def assignable_role!(role_id)
            role = current_user.account.roles.find(role_id)
            return role if current_user.can_assign_role?(role)

            raise ActiveRecord::RecordNotFound
        end

        def invite_params
            params.require(:invite).permit(
                :email,
                :full_name,
                :telephone,
                :notes,
                :role_id
            )
        end
    end
end
