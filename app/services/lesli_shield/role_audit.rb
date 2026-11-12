# frozen_string_literal: true

module LesliShield
    # Defines the durable audit vocabulary for role administration.
    class RoleAudit
        EVENT_DESCRIPTIONS = {
            "role_created" => "Role created",
            "role_updated" => "Role updated",
            "role_deactivated" => "Role deactivated",
            "role_activated" => "Role activated",
            "role_duplicated" => "Role duplicated",
            "role_deleted" => "Role deleted",
            "role_privileges_deployed" => "Role privileges deployed"
        }.freeze

        class << self
            # Call inside the mutation's transaction. Audit persistence errors
            # must propagate so the role and its event cannot diverge.
            def record!(operation, role:, actor:, source:, details: {})
                operation = operation.to_s
                description = EVENT_DESCRIPTIONS.fetch(operation)

                raise ArgumentError, "audit actor is required" unless actor

                actor.log(
                    engine: LesliShield,
                    source: source,
                    action: operation,
                    operation: operation,
                    description: description,
                    subject: role,
                    details: details.merge(
                        role_id: role.id,
                        role_name: role.name,
                        role_active: role.active?,
                        account_id: role.account_id
                    )
                )
            end
        end
    end
end
