# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RolePrivilegeDeploymentServiceTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        test "compiles privileges and records exactly one audit event" do
            context = insert_account_context("privilege-deploy")
            role = insert_role(
                context,
                name: "Deployed role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Deployed action")
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

        test "rolls privilege compilation back when audit persistence fails" do
            context = insert_account_context("failed-privilege-deploy")
            role = insert_role(
                context,
                name: "Rollback role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Rollback action")
            actor = context.fetch(:user)

            actor.define_singleton_method(:log) do |**|
                raise ActiveRecord::RecordInvalid
            end

            assert_raises(ActiveRecord::RecordInvalid) do
                RolePrivilegeDeploymentService.new(actor).deploy!(role)
            end

            refute Role::Privilege.exists?(
                role: role,
                controller: role_action.action.parent.route,
                action: role_action.action.action
            )
            assert_nil role.reload.deployed_at
        end

        private

        def capture_audit_events(actor)
            events = []
            actor.define_singleton_method(:log) do |**attributes|
                events << attributes
            end
            events
        end
    end
end
