# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RolePermissionServiceTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        test "builds a complete grouped matrix with readable and technical names" do
            context = insert_account_context("permission-matrix")
            role = insert_role(
                context,
                name: "Matrix role",
                permission_level: 50
            )
            resource = create_resource(
                engine: "lesli_shield",
                identifier: "Invites",
                label: "Invitaciones",
                route: "lesli_shield/invites"
            )
            index_action = create_action(
                resource,
                action: "index",
                label: "Listar invitaciones"
            )
            create_action(resource, action: "resend", label: "Reenviar")
            create_action(resource, action: "destroy", label: "Eliminar")
            create_action(resource, action: "create", label: "Crear")
            unassigned_action = create_action(
                resource,
                action: "show",
                label: "Ver invitación"
            )
            assigned = Role::Action.create!(role: role, action: index_action)
            removed = Role::Action.create!(role: role, action: unassigned_action)
            removed.delete

            deleted_resource = create_resource(
                engine: "lesli_shield",
                identifier: "Deleted",
                label: "Deleted",
                route: "lesli_shield/deleted"
            )
            create_action(deleted_resource, action: "index", label: "Deleted index")
            deleted_resource.delete

            matrix = RolePermissionService
                .new(context.fetch(:user))
                .matrix(role)
            engine = matrix.find { |entry| entry[:engine] == "lesli_shield" }
            matrix_resource = engine[:resources].find do |entry|
                entry[:route] == "lesli_shield/invites"
            end

            assert_equal "LesliShield", engine[:label]
            assert_equal "Invitaciones", matrix_resource[:label]
            assert_equal "Invites", matrix_resource[:identifier]
            assert_equal(
                %w[index show create destroy resend],
                matrix_resource[:actions].pluck(:action)
            )

            index_permission = matrix_resource[:actions].find do |action|
                action[:action] == "index"
            end
            show_permission = matrix_resource[:actions].find do |action|
                action[:action] == "show"
            end
            assert_equal "Listar invitaciones", index_permission[:label]
            assert_equal I18n.t(
                "lesli_shield.roles.permissions.standard_actions.index"
            ), index_permission[:display_label]
            assert_equal "index", index_permission[:identifier]
            assert index_permission[:standard]
            assert index_permission[:assigned]
            assert_equal assigned.id, index_permission[:role_action_id]
            refute show_permission[:assigned]
            assert show_permission[:standard]
            assert_equal removed.id, show_permission[:role_action_id]
            refute(
                engine[:resources].any? do |entry|
                    entry[:route] == "lesli_shield/deleted"
                end
            )
        end

        test "updates one permission without compiling effective privileges" do
            context = insert_account_context("permission-update")
            role = insert_role(
                context,
                name: "Applied role",
                permission_level: 50
            )
            resource = create_resource(
                engine: "lesli_shield",
                identifier: "Applied",
                label: "Applied",
                route: "lesli_shield/applied"
            )
            previous_action = create_action(resource, action: "index", label: "Index")
            selected_action = create_action(resource, action: "show", label: "Show")
            previous_selection = Role::Action.create!(
                role: role,
                action: previous_action
            )
            deployed_at = 1.day.ago
            role.update!(deployed_at: deployed_at)
            privilege = Role::Privilege.create!(
                role: role,
                controller: resource.route,
                action: previous_action.action,
                active: true
            )
            service = RolePermissionService.new(context.fetch(:user))

            service.set!(
                role: role,
                action_id: selected_action.id.to_s,
                enabled: true
            )

            assert_nil previous_selection.reload.deleted_at
            assert role.actions.exists?(action_id: selected_action.id)
            assert_not_nil role.reload.modified_at
            assert_equal deployed_at.to_i, role.deployed_at.to_i
            assert_equal privilege, role.privileges.find(privilege.id)

            modified_at = role.modified_at
            service.set!(
                role: role,
                action_id: selected_action.id,
                enabled: true
            )
            assert_equal modified_at, role.reload.modified_at

            service.set!(
                role: role,
                action_id: previous_action.id,
                enabled: false
            )
            assert_not_nil previous_selection.reload.deleted_at
            assert role.actions.exists?(action_id: selected_action.id)

            unknown_error = assert_raises(
                RolePermissionService::UnknownActionsError
            ) do
                service.set!(
                    role: role,
                    action_id: resource.id,
                    enabled: true
                )
            end
            assert_includes unknown_error.action_ids, resource.id

            malformed_error = assert_raises(
                RolePermissionService::UnknownActionsError
            ) do
                service.set!(role: role, action_id: "invalid", enabled: true)
            end
            assert_includes malformed_error.action_ids, "invalid"
        end

        test "does not audit changes to the permission selection" do
            context = insert_account_context("permission-without-audit")
            role = insert_role(
                context,
                name: "Permission without audit role",
                permission_level: 50
            )
            resource = create_resource(
                engine: "lesli_shield",
                identifier: "WithoutAudit",
                label: "Without audit",
                route: "lesli_shield/without_audit"
            )
            action = create_action(resource, action: "index", label: "Index")
            actor = context.fetch(:user)
            actor.define_singleton_method(:log) do |**|
                raise "permission selection must not emit audit events"
            end

            RolePermissionService.new(actor).set!(
                role: role,
                action_id: action.id,
                enabled: true
            )

            assert role.actions.exists?(action_id: action.id)
            assert_not_nil role.reload.modified_at
        end

        test "duplicates only active catalog selections" do
            context = insert_account_context("permission-duplicate")
            source = insert_role(
                context,
                name: "Permission source",
                permission_level: 50
            )
            target = insert_role(
                context,
                name: "Permission target",
                permission_level: 40
            )
            resource = create_resource(
                engine: "lesli_shield",
                identifier: "Duplicate",
                label: "Duplicate",
                route: "lesli_shield/duplicate"
            )
            copied_action = create_action(resource, action: "index", label: "Index")
            deleted_action = create_action(resource, action: "show", label: "Show")
            Role::Action.create!(role: source, action: copied_action)
            Role::Action.create!(role: source, action: deleted_action)
            deleted_action.delete
            target_action = create_action(resource, action: "update", label: "Update")
            old_target_selection = Role::Action.create!(
                role: target,
                action: target_action
            )
            existing_cache = Role::Privilege.create!(
                role: target,
                controller: "legacy",
                action: "show",
                active: true
            )

            RolePermissionService
                .new(context.fetch(:user))
                .duplicate_from!(source, target)

            assert_equal [copied_action.id], target.actions.pluck(:action_id)
            assert_not_nil old_target_selection.reload.deleted_at
            assert_equal existing_cache, target.privileges.find(existing_cache.id)
        end

        test "returns only permissions that currently authorize" do
            context = insert_account_context("effective-permissions")
            role = insert_role(
                context,
                name: "Effective role",
                permission_level: 50
            )
            Role::Privilege.create!(
                role: role,
                controller: "lesli_shield/invites",
                action: "index",
                active: true
            )
            Role::Privilege.create!(
                role: role,
                controller: "lesli_shield/invites",
                action: "destroy",
                active: false
            )
            deleted = Role::Privilege.create!(
                role: role,
                controller: "lesli_shield/users",
                action: "index",
                active: true
            )
            deleted.delete
            service = RolePermissionService.new(context.fetch(:user))

            assert_equal(
                [{ controller: "lesli_shield/invites", action: "index" }],
                service.effective_permissions(role)
            )

            role.update!(active: false)
            assert_empty service.effective_permissions(role)
        end

        test "applies role security boundaries to the permission service" do
            context = insert_account_context("permission-security")
            other_context = insert_account_context("permission-security-other")
            owner = insert_role(
                context,
                name: "Owner",
                permission_level: 100,
                system_name: "owner"
            )
            foreign_role = insert_role(
                other_context,
                name: "Foreign permission role",
                permission_level: 50
            )
            service = RolePermissionService.new(context.fetch(:user))

            assert_raises(ActiveRecord::RecordNotFound) { service.matrix(owner) }
            assert_raises(ActiveRecord::RecordNotFound) do
                service.set!(
                    role: foreign_role,
                    action_id: 1,
                    enabled: true
                )
            end
        end

        private

        def create_resource(engine:, identifier:, label:, route:)
            Lesli::Resource.create!(
                engine: engine,
                identifier: identifier,
                label: label,
                route: route
            )
        end

        def create_action(resource, action:, label:)
            resource.children.create!(
                action: action,
                identifier: action,
                label: label
            )
        end

    end
end
