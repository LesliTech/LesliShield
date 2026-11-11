# frozen_string_literal: true

module LesliShield
    # Provides one explicit audit vocabulary for the invitation lifecycle.
    # This component does not hide persistence errors; each caller decides
    # whether the event belongs to a database transaction or an async delivery.
    class InvitationAudit
        EVENT_DESCRIPTIONS = {
            "invitation_sent" => "Invitation delivered",
            "invitation_resent" => "Invitation delivered again",
            "invitation_cancelled" => "Invitation cancelled",
            "invitation_accepted" => "Invitation accepted",
            "invitation_delivery_failed" => "Invitation delivery failed"
        }.freeze

        class << self
            def record!(operation, invitation:, actor:, source:)
                operation = operation.to_s
                description = EVENT_DESCRIPTIONS.fetch(operation)

                raise ArgumentError, "audit actor is required" unless actor

                actor.log(
                    engine: LesliShield,
                    source: source,
                    action: operation,
                    operation: operation,
                    description: description,
                    subject: invitation
                )
            end
        end
    end
end
