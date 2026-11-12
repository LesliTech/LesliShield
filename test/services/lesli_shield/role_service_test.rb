# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RoleServiceTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        test "finds roles only inside the account and permission boundary" do
            current_context = insert_account_context("service-find-current")
            other_context = insert_account_context("service-find-other")
            visible = insert_role(
                current_context,
                name: "Visible service role",
                permission_level: 50
            )
            higher = insert_role(
                current_context,
                name: "Higher service role",
                permission_level: 101
            )
            foreign = insert_role(
                other_context,
                name: "Foreign service role",
                permission_level: 50
            )
            service = RoleService.new(current_context.fetch(:user))

            assert_equal visible, service.find!(visible.id)
            assert_raises(ActiveRecord::RecordNotFound) { service.find!(higher.id) }
            assert_raises(ActiveRecord::RecordNotFound) { service.find!(foreign.id) }
        end

        test "creates normalized roles with safe defaults and unique names" do
            context = insert_account_context("service-create")
            service = RoleService.new(context.fetch(:user))

            role = service.create!(
                name: "  Support   manager  ",
                description: "  Handles   customer requests  "
            )

            assert_equal "Support manager", role.name
            assert_equal "Handles customer requests", role.description
            assert_predicate role, :active?
            assert_equal 10, role.permission_level
            refute role.isolated?
            refute role.path_limited?

            duplicate_error = assert_raises(RoleService::DuplicateNameError) do
                service.create!(name: " support MANAGER ")
            end
            assert_equal "support MANAGER", duplicate_error.record.name

            assert_raises(RoleService::PermissionLevelError) do
                service.create!(name: "Elevated", permission_level: 101)
            end
        end

        test "updates and deactivates manageable roles but protects owner" do
            context = insert_account_context("service-update")
            role = insert_role(
                context,
                name: "Editable role",
                permission_level: 50
            )
            owner = insert_role(
                context,
                name: "Owner",
                permission_level: 100,
                system_name: "owner"
            )
            service = RoleService.new(context.fetch(:user))

            service.update!(
                role,
                name: "  Updated   role ",
                description: "  Updated   description "
            )
            assert_equal "Updated role", role.reload.name
            assert_equal "Updated description", role.description

            service.deactivate!(role)
            refute role.reload.active?

            assert_raises(RoleService::ProtectedRoleError) do
                service.update!(owner, name: "Changed owner")
            end
            assert_raises(RoleService::ProtectedRoleError) do
                service.deactivate!(owner)
            end
        end

        test "deletes only unassigned custom roles" do
            context = insert_account_context("service-destroy")
            service = RoleService.new(context.fetch(:user))
            custom = insert_role(
                context,
                name: "Disposable role",
                permission_level: 30
            )
            assigned = insert_role(
                context,
                name: "Assigned role",
                permission_level: 30
            )
            system = insert_role(
                context,
                name: "Admin",
                permission_level: 90,
                system_name: "admin"
            )
            assign_role(context.fetch(:user), assigned)

            assert_raises(RoleService::AssignedUsersError) do
                service.destroy!(assigned)
            end
            assert_raises(RoleService::SystemRoleError) do
                service.destroy!(system)
            end

            assert_equal custom, service.destroy!(custom)
            refute context.fetch(:account).roles.exists?(custom.id)
        end

        test "duplicates configuration and active actions without assignments or cache" do
            context = insert_account_context("service-duplicate")
            source = insert_role(
                context,
                name: "Operations",
                permission_level: 40
            )
            source.update!(
                description: "Operations access",
                path_default: "/operations",
                deployed_at: Time.current
            )
            insert_role_action(source, label: "Active source action")
            deleted_action = insert_role_action(source, label: "Deleted source action")
            deleted_action.delete
            Role::Privilege.create!(
                role: source,
                controller: "operations",
                action: "index",
                active: true
            )

            duplicate = RoleService
                .new(context.fetch(:user))
                .duplicate!(source)

            assert_equal "Operations copy", duplicate.name
            assert_equal source.description, duplicate.description
            assert_equal source.path_default, duplicate.path_default
            assert_equal source.permission_level, duplicate.permission_level
            refute_predicate duplicate, :active?
            assert_nil duplicate.deployed_at
            assert_not_nil duplicate.modified_at
            assert_equal 1, duplicate.actions.count
            assert_equal 0, duplicate.privileges.count
            refute User::Role.where(role: duplicate).exists?
        end

        test "lists normalized counts with search status sorting and pagination" do
            context = insert_account_context("service-list")
            alpha = insert_role(
                context,
                name: "Alpha role",
                permission_level: 40
            )
            beta = insert_role(
                context,
                name: "Beta role",
                permission_level: 30
            )
            inactive = insert_role(
                context,
                name: "Inactive role",
                permission_level: 20
            )
            alpha.update!(description: "Pagination needle")
            beta.update!(description: "Pagination needle")
            inactive.update!(active: false, description: "Inactive needle")

            assign_role(context.fetch(:user), alpha)
            inactive_user = insert_user(context, active: false)
            assign_role(inactive_user, alpha)

            insert_role_action(alpha, label: "Active count action")
            deleted_action = insert_role_action(alpha, label: "Deleted count action")
            deleted_action.delete

            query = {
                search: "pagination needle",
                pagination: { page: 2, perPage: 1 },
                order: { by: "name", dir: "asc" }
            }
            page = RoleService.new(context.fetch(:user), query).list(status: "active")

            assert_equal 2, page.total_count
            assert_equal 2, page.total_pages
            assert_equal [beta.id], page.map(&:id)

            counted_alpha = RoleService.new(
                context.fetch(:user),
                {
                    search: "alpha",
                    pagination: { page: 1, perPage: 10 },
                    order: { by: "users", dir: "desc" }
                }
            ).list.first
            assert_equal 1, counted_alpha[:users]
            assert_equal 1, counted_alpha[:actions]

            users_order = RoleService.new(
                context.fetch(:user),
                {
                    search: "pagination needle",
                    pagination: { page: 1, perPage: 10 },
                    order: { by: "users", dir: "desc" }
                }
            ).list
            assert_equal [alpha.id, beta.id], users_order.map(&:id)

            inactive_roles = RoleService.new(
                context.fetch(:user),
                pagination: { page: 1, perPage: 10 },
                order: { by: "id", dir: "asc" }
            ).list(status: "inactive")
            assert_equal [inactive.id], inactive_roles.map(&:id)
        end

        test "filters system and custom roles using the role domain contract" do
            context = insert_account_context("service-role-types")
            system_role = insert_role(
                context,
                name: "Admin",
                permission_level: 90,
                system_name: "admin"
            )
            custom_role = insert_role(
                context,
                name: "Support team",
                permission_level: 30
            )
            service = RoleService.new(
                context.fetch(:user),
                pagination: { page: 1, perPage: 20 },
                order: { by: "name", dir: "asc" }
            )

            system_roles = service.list(type: "system")
            custom_roles = service.list(type: "custom")

            assert_equal [system_role.id], system_roles.map(&:id)
            assert_includes custom_roles.map(&:id), custom_role.id
            assert_includes custom_roles.map(&:id), context.fetch(:manager_role).id
            refute_includes custom_roles.map(&:id), system_role.id
        end

        private

        def insert_user(context, active:)
            identifier = SecureRandom.hex(5)
            timestamp = Time.current
            user_id = Lesli::User.insert_all!([{
                account_id: context.fetch(:account).id,
                uid: "ROLE-SERVICE-#{identifier.upcase}",
                email: "role-service-#{identifier}@example.com",
                encrypted_password: "",
                active: active,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            Lesli::User.find(user_id)
        end
    end
end
