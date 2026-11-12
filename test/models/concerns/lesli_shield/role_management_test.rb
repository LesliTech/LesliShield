# frozen_string_literal: true

require "test_helper"

module LesliShield
    class RoleManagementTest < ActiveSupport::TestCase
        Actor = Data.define(:account_id, :max_level_permission)

        test "requires every role to belong to one account" do
            role = build_role(account_id: nil)

            refute role.valid?
            assert_includes role.errors[:account], "must exist"
        end

        test "identifies system and protected roles by their stable identifier" do
            owner = build_role(id: 42, name: "Renamed owner", code: "owner42")
            admin = build_role(id: 7, name: "Administrator", code: "admin7")
            guest = build_role(id: 3, name: "Guest", code: "guest3")
            custom = build_role(id: 9, name: "Support manager", code: "support_manager9")

            assert_predicate owner, :system_role?
            assert_predicate owner, :protected_role?
            assert_predicate admin, :system_role?
            refute_predicate admin, :protected_role?
            assert_predicate guest, :system_role?
            refute_predicate custom, :system_role?
            refute_predicate custom, :protected_role?
        end

        test "allows management only inside the actor account and permission boundary" do
            actor = Actor.new(account_id: 10, max_level_permission: 100)

            assert build_role(account_id: 10, permission_level: 100).manageable_by?(actor)
            assert build_role(account_id: 10, permission_level: 90).manageable_by?(actor)
            refute build_role(account_id: 10, permission_level: 101).manageable_by?(actor)
            refute build_role(account_id: 11, permission_level: 90).manageable_by?(actor)
            refute build_role(
                account_id: 10,
                permission_level: 1,
                id: 1,
                name: "Owner",
                code: "owner1"
            ).manageable_by?(actor)
        end

        test "allows deletion only for unassigned custom roles" do
            actor = Actor.new(account_id: 10, max_level_permission: 100)
            custom_role = build_role(account_id: 10, permission_level: 50)
            assigned_role = build_role(account_id: 10, permission_level: 50)
            system_role = build_role(
                account_id: 10,
                permission_level: 50,
                id: 2,
                name: "Admin",
                code: "admin2"
            )

            custom_role.define_singleton_method(:assigned?) { false }
            assigned_role.define_singleton_method(:assigned?) { true }
            system_role.define_singleton_method(:assigned?) { false }

            assert custom_role.deletable_by?(actor)
            refute assigned_role.deletable_by?(actor)
            refute system_role.deletable_by?(actor)
        end

        test "inactive roles preserve assignments and permissions without authorizing" do
            context = insert_authorization_context
            user = context.fetch(:user)
            role = context.fetch(:role)

            assert user.has_privileges_for?("lesli_shield/invites", "index")
            assert_predicate role, :assigned?
            assert_predicate role, :active?

            role.update!(active: false)

            refute user.has_privileges_for?("lesli_shield/invites", "index")
            refute_predicate role, :active?
            assert_predicate role, :assigned?
            assert Role::Privilege.where(role_id: role.id).exists?
        end

        private

        def build_role(
            id: nil,
            account_id: 10,
            permission_level: 50,
            name: "Support manager",
            code: "support_manager9"
        )
            Lesli::Role.new(
                id: id,
                account_id: account_id,
                permission_level: permission_level,
                name: name,
                code: code,
                active: true
            )
        end

        def insert_authorization_context
            identifier = SecureRandom.hex(6)
            timestamp = Time.current
            account_id = Lesli::Account.insert_all!([{
                email: "role-contract-account-#{identifier}@example.com",
                name: "Role contract #{identifier}",
                status: "active",
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            user_id = Lesli::User.insert_all!([{
                account_id: account_id,
                uid: "ROLE-CONTRACT-#{identifier.upcase}",
                email: "role-contract-user-#{identifier}@example.com",
                encrypted_password: "",
                active: true,
                confirmed_at: timestamp,
                sign_in_count: 0,
                failed_attempts: 0,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            role_id = Lesli::Role.insert_all!([{
                account_id: account_id,
                name: "Contract role #{identifier}",
                code: "contract_role_#{identifier}",
                permission_level: 50,
                active: true,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first

            User::Role.create!(user_id: user_id, role_id: role_id)
            Role::Privilege.create!(
                role_id: role_id,
                controller: "lesli_shield/invites",
                action: "index",
                active: true
            )

            {
                user: Lesli::User.find(user_id),
                role: Lesli::Role.find(role_id)
            }
        end
    end
end
