# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RolePermissionConcurrencyTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        self.use_transactional_tests = false

        setup do
            @context = insert_account_context("permission-concurrency")
            @role = insert_role(
                @context,
                name: "Concurrent permission role",
                permission_level: 50
            )
            @resource = Lesli::Resource.create!(
                engine: "lesli_shield",
                identifier: "ConcurrentPermissions",
                label: "Concurrent permissions",
                route: "lesli_shield/concurrent_permissions"
            )
            @first_action = create_action("index")
            @second_action = create_action("show")
        end

        teardown do
            cleanup_records
        end

        test "concurrent changes do not replace permissions from other requests" do
            ready = Queue.new
            start = Queue.new
            requested_action_ids = [@first_action.id, @second_action.id]

            attempts = requested_action_ids.map do |action_id|
                Thread.new do
                    ActiveRecord::Base.connection_pool.with_connection do
                        actor = Lesli::User.find(@context.fetch(:user).id)
                        ready << true
                        start.pop

                        begin
                            RolePermissionService.new(actor).set!(
                                role: @role.id,
                                action_id: action_id,
                                enabled: true
                            )
                        rescue StandardError => exception
                            exception
                        end
                    end
                end
            end

            2.times { ready.pop }
            2.times { start << true }
            results = attempts.map(&:value)
            errors = results.grep(Exception)

            assert results.any? { |result| result.is_a?(Lesli::Role) }
            errors.each do |error|
                assert_kind_of ActiveRecord::StatementInvalid, error
            end

            active_ids = @role.actions.order(:action_id).pluck(:action_id)
            successful_action_ids = requested_action_ids.zip(results).filter_map do |action_id, result|
                action_id if result.is_a?(Lesli::Role)
            end
            assert_equal successful_action_ids.sort, active_ids
            assert_not_nil @role.reload.modified_at
        end

        private

        def create_action(action_name)
            @resource.children.create!(
                action: action_name,
                identifier: action_name,
                label: action_name.humanize
            )
        end

        def cleanup_records
            role_ids = [@role&.id, @context&.dig(:manager_role)&.id].compact
            user_ids = [@context&.dig(:user)&.id].compact
            resource_ids = [
                @first_action&.id,
                @second_action&.id,
                @resource&.id
            ].compact

            Role::Privilege.unscoped.where(role_id: role_ids).delete_all!
            Role::Action.unscoped.where(role_id: role_ids).delete_all!
            User::Role.unscoped.where(
                user_id: user_ids,
                role_id: role_ids
            ).delete_all!
            Lesli::Resource.unscoped.where(id: resource_ids).delete_all!
            Lesli::Role.unscoped.where(id: role_ids).delete_all!
            Lesli::User.unscoped.where(id: user_ids).delete_all!
            # The shared context creates these account extensions explicitly.
            # Remove them before their core account to respect the foreign keys.
            if defined?(LesliAudit)
                LesliAudit::Account.unscoped.where(account_id: @context&.dig(:account)&.id).delete_all!
            end
            if defined?(LesliBell)
                LesliBell::Account.unscoped.where(account_id: @context&.dig(:account)&.id).delete_all!
            end
            Lesli::Account.unscoped
                .where(id: @context&.dig(:account)&.id)
                .delete_all!
        end
    end
end
