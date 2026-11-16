# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RoleAuditTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        class AuditFailure < StandardError; end

        setup do
            @original_audit_config = Lesli.config.audit.dup
            skip "Persistent audit integration requires LesliAudit" unless defined?(LesliAudit)
            Lesli.config.audit[:enable_logs] = true
            @context = insert_account_context("role-audit")
            @actor = @context.fetch(:user)
            @service = RoleService.new(@actor)
            @role = insert_role(@context, name: "Support", permission_level: 40)
        end

        teardown do
            Lesli.config.audit.replace(@original_audit_config)
        end

        test "creation records one durable event with the actor account and role" do
            role = nil
            assert_difference -> { events.count }, 1 do
                role = @service.create!(name: "New role", permission_level: 30)
            end

            event = events.last
            assert_equal "role_created", event.operation
            assert_equal "role_created", event.action
            assert_equal "LesliShield::RoleService", event.source
            assert_equal @actor.id, event.user_id
            assert_equal @actor.uid, event.actor_uid
            assert_equal @context.fetch(:account).audit.id, event.account_id
            assert_equal "Lesli::Role", event.subject_type
            assert_equal role.id, event.subject_id
            assert_equal role.id, event.details.fetch("role_id")
            assert_equal role.name, event.details.fetch("role_name")
            assert_equal role.account_id, event.details.fetch("account_id")
        end

        test "updates record before and after values only when something changes" do
            assert_difference -> { events.count }, 1 do
                @service.update!(@role, name: "  Customer   support  ", permission_level: 30)
            end
            event = events.last
            assert_equal "role_updated", event.operation
            assert_equal(
                { "name" => ["Support", "Customer support"], "permission_level" => [40, 30] },
                event.details.fetch("changes")
            )

            timestamp = @role.reload.updated_at
            assert_no_difference -> { events.count } do
                @service.update!(@role, name: " Customer  support ", active: "1")
                @service.update!(@role, {})
            end
            assert_equal timestamp, @role.reload.updated_at
        end

        test "status transitions record one specific event including other edits" do
            assert_difference -> { events.count }, 1 do
                @service.update!(@role, active: false, description: "Temporarily disabled")
            end
            assert_equal "role_deactivated", events.last.operation
            assert_equal [true, false], events.last.details.fetch("changes").fetch("active")
            assert_equal [nil, "Temporarily disabled"], events.last.details.fetch("changes").fetch("description")

            assert_no_difference -> { events.count } do
                @service.deactivate!(@role)
            end
            assert_difference -> { events.count }, 1 do
                @service.update!(@role, active: true)
            end
            assert_equal "role_activated", events.last.operation
            assert_difference -> { events.count }, 1 do
                @service.deactivate!(@role)
            end
            assert_equal "role_deactivated", events.last.operation
        end

        test "duplication records only its own event and identifies the source" do
            insert_role_action(@role, label: "Copied action")
            duplicate = nil
            assert_difference -> { events.count }, 1 do
                duplicate = @service.duplicate!(@role)
            end
            event = events.last
            assert_equal "role_duplicated", event.operation
            assert_equal duplicate.id, event.subject_id
            assert_equal @role.id, event.details.fetch("source_role_id")
            assert_equal @role.name, event.details.fetch("source_role_name")
            assert_equal 1, duplicate.actions.count
        end

        test "deletion preserves the role identity in its audit event" do
            assert_difference -> { events.count }, 1 do
                @service.destroy!(@role)
            end
            event = events.last
            assert_equal "role_deleted", event.operation
            assert_equal @role.id, event.subject_id
            assert_equal "Support", event.details.fetch("role_name")
            refute Lesli::Role.exists?(@role.id)
        end

        test "rejected operations do not create events" do
            foreign_context = insert_account_context("foreign-role-audit")
            foreign_role = insert_role(foreign_context, name: "Foreign", permission_level: 30)
            assert_no_difference -> { events.count } do
                assert_raises(RoleService::PermissionLevelError) do
                    @service.update!(@role, permission_level: 101)
                end
                assert_raises(RoleService::ValidationError) do
                    @service.create!(name: "", permission_level: 30)
                end
                assert_raises(ActiveRecord::RecordNotFound) do
                    @service.update!(foreign_role, name: "Tampered")
                end
            end
        end

        test "creation and duplication roll back their records and events on audit failure" do
            insert_role_action(@role, label: "Rollback copy action")
            fail_after_audit_write!

            assert_no_difference [-> { Lesli::Role.count }, -> { Role::Action.count }, -> { events.count }] do
                assert_raises(AuditFailure) do
                    @service.create!(name: "Failed creation", permission_level: 20)
                end
                assert_raises(AuditFailure) do
                    @service.duplicate!(@role)
                end
            end
        end

        test "updates and status changes roll back along with the event" do
            fail_after_audit_write!

            assert_no_difference -> { events.count } do
                assert_raises(AuditFailure) do
                    @service.update!(@role, name: "Failed update", permission_level: 20)
                end
                assert_equal "Support", @role.reload.name
                assert_equal 40, @role.permission_level

                assert_raises(AuditFailure) { @service.deactivate!(@role) }
                assert_predicate @role.reload, :active?
            end
        end

        test "deletion restores the role and its permissions when auditing fails" do
            selection = insert_role_action(@role, label: "Rollback deletion")
            privilege = Role::Privilege.create!(role: @role, controller: "support", action: "index", active: true)
            fail_after_audit_write!

            assert_no_difference -> { events.count } do
                assert_raises(AuditFailure) { @service.destroy!(@role) }
            end
            assert Lesli::Role.exists?(@role.id)
            assert Role::Action.exists?(selection.id)
            assert Role::Privilege.exists?(privilege.id)
        end

        private

        def events
            LesliAudit::UserLog.where(user_id: @actor.id)
        end

        # Fail after the INSERT to verify that the surrounding transaction
        # rolls back the business change and the audit row together.
        def fail_after_audit_write!
            original_log = @actor.method(:log)
            @actor.define_singleton_method(:log) do |**attributes|
                original_log.call(**attributes)
                raise AuditFailure, "Audit write failed"
            end
        end
    end
end
