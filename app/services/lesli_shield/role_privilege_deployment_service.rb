# frozen_string_literal: true

module LesliShield
    # Compiles a role's selected actions into its effective privilege cache.
    # The compilation and its audit event are one atomic operation.
    class RolePrivilegeDeploymentService
        def initialize(actor)
            @actor = actor
        end

        def deploy!(role)
            raise ActiveRecord::RecordNotFound unless role&.manageable_by?(actor)

            role.with_lock do
                RolePrivilegeService.new(actor).synchronize(role)
                role.touch(:deployed_at)
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

        attr_reader :actor
    end
end
