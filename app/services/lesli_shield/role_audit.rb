# frozen_string_literal: true

module LesliShield
    # Defines the durable audit vocabulary for role administration.
    class RoleAudit
        EVENT_DESCRIPTIONS = {
            "role_permissions_saved" => "Role permissions saved",
            "role_privileges_deployed" => "Role privileges deployed"
        }.freeze

        class << self
            def record!(operation, role:, actor:, source:)
                operation = operation.to_s
                description = EVENT_DESCRIPTIONS.fetch(operation)

                raise ArgumentError, "audit actor is required" unless actor

                actor.log(
                    engine: LesliShield,
                    source: source,
                    action: operation,
                    operation: operation,
                    description: description,
                    subject: role
                )
            end
        end
    end
end
