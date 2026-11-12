# frozen_string_literal: true

module LesliShield
    # Compiles a role's selected actions into its effective privilege cache.
    # The compilation and its audit event are one atomic operation.
    class RolePrivilegeDeploymentService
        def initialize(actor)
            @actor = actor
            @role_service = RoleService.new(actor)
        end

        def deploy!(role_or_id)
            role = manageable_role!(role_or_id)

            role.with_lock do
                # Revalidate after waiting for the lock because the actor's
                # account or permission boundary may have changed.
                manageable_role!(role.id)
                timestamp = Time.current

                RolePrivilegeService.new.rebuild!(
                    role,
                    timestamp: timestamp
                )
                role.update_columns(
                    deployed_at: timestamp,
                    updated_at: timestamp
                )
                RoleAudit.record!(
                    :role_privileges_deployed,
                    role: role,
                    actor: actor,
                    source: self.class
                )
            end

            role
        end

        private

        attr_reader :actor, :role_service

        def manageable_role!(role_or_id)
            role_id = role_or_id.respond_to?(:id) ? role_or_id.id : role_or_id
            role_service.find!(role_id, manageable: true)
        end
    end
end
