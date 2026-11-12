# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RoleActionsControllerTest < ActionController::TestCase
        include RoleSecurityTestHelpers

        tests Role::ActionsController

        test "loads an action only through the selected role" do
            context = insert_account_context("nested-actions")
            selected_role = insert_role(
                context,
                name: "Selected role",
                permission_level: 50
            )
            another_role = insert_role(
                context,
                name: "Another role",
                permission_level: 40
            )
            selected_action = insert_role_action(selected_role, label: "Selected")
            another_action = insert_role_action(another_role, label: "Another")

            with_current_user(context.fetch(:user)) do
                @controller.params = {
                    role_id: selected_role.id,
                    id: selected_action.id
                }
                @controller.send(:set_role)
                @controller.send(:set_role_action)
                assert_equal selected_action,
                    @controller.instance_variable_get(:@role_action)

                @controller.params = {
                    role_id: selected_role.id,
                    id: another_action.id
                }
                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:set_role_action)
                end
            end
        end

        test "rejects actions and roles belonging to another account" do
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
            foreign_action = insert_role_action(foreign_role, label: "Foreign")

            with_current_user(current_context.fetch(:user)) do
                @controller.params = { role_id: foreign_role.id }
                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:set_role)
                end

                @controller.params = {
                    role_id: current_role.id,
                    id: foreign_action.id
                }
                @controller.send(:set_role)
                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:set_role_action)
                end
            end
        end

        test "rejects permission management for a higher role" do
            context = insert_account_context("higher-action-role")
            higher_role = insert_role(
                context,
                name: "Higher role",
                permission_level: 101
            )

            with_current_user(context.fetch(:user)) do
                @controller.params = { role_id: higher_role.id }

                assert_raises(ActiveRecord::RecordNotFound) do
                    @controller.send(:set_role)
                end
            end
        end

        test "requires the permission administration privilege" do
            context = insert_account_context("action-privilege")
            role = insert_role(
                context,
                name: "Managed role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Managed action")

            grant_privilege(
                context,
                controller: "lesli_shield/roles",
                action: "show"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }
                assert_response :forbidden

                patch :update, params: {
                    role_id: role.id,
                    id: role_action.id
                }
                assert_response :forbidden

                delete :destroy, params: {
                    role_id: role.id,
                    id: role_action.id
                }
                assert_response :forbidden
            end


            assert_nil role_action.reload.deleted_at

            grant_privilege(
                context,
                controller: "lesli_shield/role/actions",
                action: "index"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }
                assert_response :success
            end
        end

        test "updates the selected permissions without deploying the role" do
            context = insert_account_context("action-selection")
            role = insert_role(
                context,
                name: "Permission selection role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Selectable action")
            role_action.delete
            deployed_at = 1.day.ago
            role.update_columns(modified_at: nil, deployed_at: deployed_at)

            with_authorized_request(context.fetch(:user)) do
                patch :update,
                    params: { role_id: role.id, id: role_action.id },
                    format: :turbo_stream

                assert_response :success
                assert_nil role_action.reload.deleted_at
                assert_not_nil role.reload.modified_at
                assert_equal deployed_at.to_i, role.deployed_at.to_i

                delete :destroy,
                    params: { role_id: role.id, id: role_action.id },
                    format: :turbo_stream

                assert_response :success
                assert_not_nil role_action.reload.deleted_at
                assert_equal deployed_at.to_i, role.reload.deployed_at.to_i
            end
        end

        test "does not expose routes for the unimplemented privileges controller" do
            privilege_routes = LesliShield::Engine.routes.routes.select do |route|
                route.defaults[:controller] == "lesli_shield/role/privileges"
            end

            assert_empty privilege_routes
        end
    end
end
