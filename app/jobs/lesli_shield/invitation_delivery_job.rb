# frozen_string_literal: true

module LesliShield
    # Delivers invitations outside the web request and turns delivery failures
    # into durable audit evidence plus an error-reporter notification.
    class InvitationDeliveryJob < ApplicationJob
        queue_as :mailers

        class << self
            def report_enqueue_failure(invitation_id, actor_id, exception)
                new.send(
                    :record_delivery_failure,
                    invitation_id,
                    actor_id,
                    exception,
                    stage: "enqueue"
                )
            end
        end

        def perform(invitation_id, acceptance_url, operation, actor_id)
            begin
                invitation = Invite.find(invitation_id)
                actor = Lesli::User.find(actor_id)
                deliver_invitation(invitation, acceptance_url)
            rescue StandardError => exception
                record_delivery_failure(
                    invitation_id,
                    actor_id,
                    exception,
                    stage: "delivery"
                )
                raise
            end

            record_delivery_success(
                operation,
                invitation: invitation,
                actor: actor
            )
        end

        private

        def record_delivery_success(operation, invitation:, actor:)
            InvitationAudit.record!(
                operation,
                invitation: invitation,
                actor: actor,
                source: self.class
            )
        rescue StandardError => exception
            # Retrying after the SMTP server accepted the message could send a
            # duplicate. Report an audit failure without retrying the delivery.
            Rails.error.report(
                exception,
                handled: true,
                context: error_context(
                    invitation.id,
                    stage: "audit_delivery_success",
                    operation: operation
                )
            )
        end

        def deliver_invitation(invitation, acceptance_url)
            InvitationMailer
                .account_invitation(invitation, acceptance_url)
                .deliver_now
        end

        def record_delivery_failure(
            invitation_id,
            actor_id,
            delivery_exception,
            stage:
        )
            invitation = Invite.find_by(id: invitation_id)
            actor = Lesli::User.find_by(id: actor_id) || invitation&.invited_by

            if invitation && actor
                record_delivery_failure_event(invitation, actor)
            end
        rescue StandardError => audit_exception
            Rails.error.report(
                audit_exception,
                handled: true,
                context: error_context(
                    invitation_id,
                    stage: "audit_delivery_failure"
                )
            )
        ensure
            Rails.error.report(
                delivery_exception,
                handled: stage == "enqueue",
                context: error_context(invitation_id, stage: stage)
            )
        end

        def record_delivery_failure_event(invitation, actor)
            InvitationAudit.record!(
                :invitation_delivery_failed,
                invitation: invitation,
                actor: actor,
                source: self.class
            )
        end

        def error_context(
            invitation_id,
            stage:,
            operation: "invitation_delivery_failed"
        )
            {
                job: self.class.name,
                operation: operation,
                invitation_id: invitation_id,
                stage: stage
            }
        end
    end
end
