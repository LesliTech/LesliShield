# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RolePrivilegeDeploymentServiceTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        setup do
            @original_audit_config = Lesli.config.audit.dup
            Lesli.config.audit[:enable_logs] = true
        end

        teardown do
            Lesli.config.audit.replace(@original_audit_config)
        end

        test "compiles privileges and records exactly one audit event" do
            context = insert_account_context("privilege-deploy")
            role = insert_role(
                context,
                name: "Deployed role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Deployed action")
            stale_privilege = Role::Privilege.create!(
                role: role,
                controller: "removed/controller",
                action: "destroy",
                active: false
            )
            audit_events = capture_audit_events(context.fetch(:user))

            RolePrivilegeDeploymentService
                .new(context.fetch(:user))
                .deploy!(role)

            privilege = Role::Privilege.find_by!(
                role: role,
                controller: role_action.action.parent.route,
                action: role_action.action.action
            )

            assert privilege.active?
            refute Role::Privilege.with_deleted.exists?(stale_privilege.id)
            assert_not_nil role.reload.deployed_at
            assert_equal 1, audit_events.length
            assert_equal "role_privileges_deployed",
                audit_events.first.fetch(:operation)
            assert_equal "role_privileges_deployed",
                audit_events.first.fetch(:action)
            assert_equal "Role privileges deployed",
                audit_events.first.fetch(:description)
            assert_equal LesliShield, audit_events.first.fetch(:engine)
            assert_equal RolePrivilegeDeploymentService,
                audit_events.first.fetch(:source)
            assert_equal role, audit_events.first.fetch(:subject)
        end

        test "removes every cached privilege when the selection is empty" do
            context = insert_account_context("empty-privilege-deploy")
            role = insert_role(
                context,
                name: "Empty deployment role",
                permission_level: 50
            )
            Role::Privilege.create!(
                role: role,
                controller: "obsolete/controller",
                action: "index",
                active: true
            )

            RolePrivilegeDeploymentService
                .new(context.fetch(:user))
                .deploy!(role)

            assert_empty Role::Privilege.with_deleted.where(role_id: role.id)
            assert_not_nil role.reload.deployed_at
            event = LesliAudit::UserLog.find_by!(subject_id: role.id, operation: "role_privileges_deployed")
            assert_empty event.details.fetch("permissions_added")
            assert_equal(
                [{ "controller" => "obsolete/controller", "action" => "index" }],
                event.details.fetch("permissions_removed")
            )
        end

        test "persists the effective permission difference and active affected users" do
            context = insert_account_context("deploy-audit-details")
            actor = context.fetch(:user)
            role = insert_role(context, name: "Audited permissions", permission_level: 40)
            retained = insert_role_action(role, label: "Retained permission").action
            added = insert_role_action(role, label: "Added permission").action
            Role::Privilege.create!(role: role, controller: retained.parent.route, action: retained.action, active: true)
            Role::Privilege.create!(role: role, controller: "removed/controller", action: "destroy", active: true)
            Role::Privilege.create!(role: role, controller: "inactive/controller", action: "index", active: false)
            deleted = Role::Privilege.create!(role: role, controller: "deleted/controller", action: "show", active: true)
            deleted.destroy!

            assign_role(actor, role)
            assign_role(insert_member(context, active: false), role)
            assign_role(insert_member(context, active: true, deleted_at: Time.current), role)
            assignment = assign_role(insert_member(context, active: true), role)
            assignment.destroy!

            events = LesliAudit::UserLog.where(user_id: actor.id, operation: "role_privileges_deployed")
            service = RolePrivilegeDeploymentService.new(actor)
            assert_difference -> { events.count }, 1 do
                service.deploy!(role)
            end

            event = events.last
            assert_equal actor.uid, event.actor_uid
            assert_equal context.fetch(:account).audit.id, event.account_id
            assert_equal role.id, event.subject_id
            assert_equal role.account_id, event.details.fetch("account_id")
            assert_equal role.name, event.details.fetch("role_name")
            assert_equal 1, event.details.fetch("affected_users_count")
            assert_equal(
                [{ "controller" => added.parent.route, "action" => added.action }],
                event.details.fetch("permissions_added")
            )
            assert_equal(
                [{ "controller" => "removed/controller", "action" => "destroy" }],
                event.details.fetch("permissions_removed")
            )

            # A requested rebuild is still one audited operation, even when
            # it produces the same permissions as the previous deployment.
            assert_difference -> { events.count }, 1 do
                service.deploy!(role)
            end
            assert_empty events.last.details.fetch("permissions_added")
            assert_empty events.last.details.fetch("permissions_removed")

            role.update!(active: false)
            service.deploy!(role)
            assert_equal 0, events.last.details.fetch("affected_users_count")
        end

        test "rolls privilege compilation back when audit persistence fails" do
            context = insert_account_context("failed-privilege-deploy")
            role = insert_role(
                context,
                name: "Rollback role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Rollback action")
            previous_cache = Role::Privilege.create!(
                role: role,
                controller: "previous/controller",
                action: "show",
                active: true
            )
            actor = context.fetch(:user)

            original_log = actor.method(:log)
            actor.define_singleton_method(:log) do |**attributes|
                original_log.call(**attributes)
                raise ActiveRecord::RecordInvalid
            end

            assert_no_difference -> { LesliAudit::UserLog.count } do
                assert_raises(ActiveRecord::RecordInvalid) do
                    RolePrivilegeDeploymentService.new(actor).deploy!(role)
                end
            end

            refute Role::Privilege.exists?(
                role: role,
                controller: role_action.action.parent.route,
                action: role_action.action.action
            )
            assert Role::Privilege.exists?(previous_cache.id)
            assert_nil role.reload.deployed_at
        end

        private

        def insert_member(context, active:, deleted_at: nil)
            identifier = SecureRandom.hex(5)
            timestamp = Time.current
            user_id = Lesli::User.unscoped.insert_all!([{
                account_id: context.fetch(:account).id,
                uid: "AUDIT-MEMBER-#{identifier}",
                email: "audit-member-#{identifier}@example.com",
                encrypted_password: "",
                active: active,
                deleted_at: deleted_at,
                created_at: timestamp,
                updated_at: timestamp
            }]).rows.first.first
            Lesli::User.with_deleted.find(user_id)
        end

        def capture_audit_events(actor)
            events = []
            actor.define_singleton_method(:log) do |**attributes|
                events << attributes
            end
            events
        end
    end
end
