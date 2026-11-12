# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RoleActionsControllerTest < ActionController::TestCase
        include RoleSecurityTestHelpers

        tests Role::ActionsController

        test "loads roles only from the current account and permission boundary" do
            current_context = insert_account_context("action-current")
            other_context = insert_account_context("action-other")
            current_role = insert_role(
                current_context,
                name: "Current role",
                permission_level: 50
            )
            foreign_role = insert_role(
                other_context,
                name: "Foreign role",
                permission_level: 50
            )
            higher_role = insert_role(
                current_context,
                name: "Higher role",
                permission_level: 101
            )

            with_current_user(current_context.fetch(:user)) do
                @controller.params = { role_id: current_role.id }
                @controller.send(:set_role)
                assert_equal current_role,
                    @controller.instance_variable_get(:@role)

                [foreign_role, higher_role].each do |inaccessible_role|
                    @controller.params = { role_id: inaccessible_role.id }
                    assert_raises(ActiveRecord::RecordNotFound) do
                        @controller.send(:set_role)
                    end
                end
            end
        end

        test "requires separate privileges to view and save permissions" do
            context = insert_account_context("action-privilege")
            role = insert_role(
                context,
                name: "Managed role",
                permission_level: 50
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }
                assert_response :forbidden

                patch :update, params: { role_id: role.id, action_ids: [] }
                assert_response :forbidden
            end

            grant_privilege(
                context,
                controller: "lesli_shield/role/actions",
                action: "index"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }
                assert_response :success

                patch :update, params: { role_id: role.id, action_ids: [] }
                assert_response :forbidden
            end
        end

        test "saves the complete selection without deploying the role" do
            context = insert_account_context("action-selection")
            role = insert_role(
                context,
                name: "Permission selection role",
                permission_level: 50
            )
            previous_selection = insert_role_action(role, label: "Previous")
            next_selection = insert_role_action(role, label: "Next")
            next_selection.delete
            deployed_at = 1.day.ago
            role.update_columns(modified_at: nil, deployed_at: deployed_at)
            cached_privilege = Role::Privilege.create!(
                role: role,
                controller: "legacy/controller",
                action: "show",
                active: true
            )

            with_authorized_request(context.fetch(:user)) do
                patch :update,
                    params: {
                        role_id: role.id,
                        action_ids: [next_selection.action_id]
                    },
                    format: :turbo_stream

                assert_response :see_other
            end

            assert_not_nil previous_selection.reload.deleted_at
            assert_nil next_selection.reload.deleted_at
            assert_not_nil role.reload.modified_at
            assert_equal deployed_at.to_i, role.deployed_at.to_i
            assert_equal cached_privilege, role.privileges.find(cached_privilege.id)
        end

        test "renders one bulk form and keeps the explicit deploy action" do
            context = insert_account_context("action-form")
            role = insert_role(
                context,
                name: "Permission form role",
                permission_level: 50
            )
            selected = insert_role_action(role, label: "Selected permission")

            with_authorized_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }

                assert_response :success
                assert_select "form[action='#{role_actions_path(role)}']" do
                    assert_select "input[name='action_ids[]'][value='#{selected.action_id}'][checked]",
                        count: 1
                    assert_select "button[type='submit']",
                        text: "Save permissions",
                        count: 1
                end
                assert_select "form[action='#{deploy_role_path(role)}']",
                    text: /Apply permissions \(deploy\)/,
                    count: 1
                assert_select ".mini-toggle", count: 0
            end
        end

        test "rejects manipulated permission identifiers atomically" do
            context = insert_account_context("action-manipulated")
            role = insert_role(
                context,
                name: "Manipulated selection role",
                permission_level: 50
            )
            selection = insert_role_action(role, label: "Unchanged")

            with_authorized_request(context.fetch(:user)) do
                patch :update,
                    params: {
                        role_id: role.id,
                        action_ids: [selection.action.parent_id, "invalid"]
                    },
                    format: :turbo_stream

                assert_response :unprocessable_content
            end

            assert_nil selection.reload.deleted_at
            assert_nil role.reload.modified_at
        end

        test "exposes one bulk update route and no individual mutation routes" do
            action_routes = LesliShield::Engine.routes.routes.select do |route|
                route.defaults[:controller] == "lesli_shield/role/actions"
            end
            route_contract = action_routes.map do |route|
                [route.defaults[:action], route.verb, route.path.spec.to_s]
            end

            assert_equal 2, action_routes.length
            assert route_contract.any? do |action, verb, path|
                action == "index" && verb.match?("GET") &&
                    !path.include?(":id")
            end
            assert route_contract.any? do |action, verb, path|
                action == "update" && verb.match?("PATCH") &&
                    !path.include?(":id")
            end
            refute route_contract.any? { |action, _verb, _path| action == "destroy" }
        end

        test "does not expose routes for the unimplemented privileges controller" do
            privilege_routes = LesliShield::Engine.routes.routes.select do |route|
                route.defaults[:controller] == "lesli_shield/role/privileges"
            end

            assert_empty privilege_routes
        end
    end
end
