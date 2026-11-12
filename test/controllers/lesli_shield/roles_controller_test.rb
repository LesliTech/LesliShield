# frozen_string_literal: true

require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RolesControllerTest < ActionController::TestCase
        include RoleSecurityTestHelpers

        tests RolesController

        test "loads roles only from the current account and permission boundary" do
            current_context = insert_account_context("roles-current")
            other_context = insert_account_context("roles-other")
            visible_role = insert_role(
                current_context,
                name: "Visible role",
                permission_level: 50
            )
            higher_role = insert_role(
                current_context,
                name: "Higher role",
                permission_level: 101
            )
            foreign_role = insert_role(
                other_context,
                name: "Foreign role",
                permission_level: 50
            )

            with_current_user(current_context.fetch(:user)) do
                @controller.params = { id: visible_role.id }
                @controller.send(:set_visible_role)
                assert_equal visible_role, @controller.instance_variable_get(:@role)

                [higher_role, foreign_role].each do |inaccessible_role|
                    @controller.params = { id: inaccessible_role.id }
                    assert_raises(ActiveRecord::RecordNotFound) do
                        @controller.send(:set_visible_role)
                    end
                end
            end
        end

        test "prevents every administrative mutation of the owner role" do
            context = insert_account_context("protected-owner")
            owner = insert_role(
                context,
                name: "Owner",
                permission_level: 100,
                system_name: "owner"
            )

            with_authorized_request(context.fetch(:user)) do
                assert_raises(ActiveRecord::RecordNotFound) do
                    get :edit, params: { id: owner.id }
                end

                assert_raises(ActiveRecord::RecordNotFound) do
                    patch :update, params: {
                        id: owner.id,
                        role: { active: false }
                    }
                end

                assert_raises(ActiveRecord::RecordNotFound) do
                    delete :destroy, params: { id: owner.id }
                end
            end

            assert owner.reload.active?
            assert context.fetch(:account).roles.exists?(owner.id)
        end

        test "does not create or elevate a role above the current user" do
            context = insert_account_context("role-level-boundary")
            role = insert_role(
                context,
                name: "Assignable role",
                permission_level: 50
            )

            with_authorized_request(context.fetch(:user)) do
                assert_raises(ActiveRecord::RecordNotFound) do
                    post :create, params: {
                        role: { name: "Elevated role", permission_level: 101 }
                    }
                end

                assert_raises(ActiveRecord::RecordNotFound) do
                    patch :update, params: {
                        id: role.id,
                        role: { permission_level: 101 }
                    }
                end
            end

            refute context.fetch(:account).roles.exists?(name: "Elevated role")
            assert_equal 50, role.reload.permission_level
        end

        test "requires a distinct administrative privilege for each role action" do
            context = insert_account_context("role-privileges")
            role = insert_role(
                context,
                name: "Visible with show privilege",
                permission_level: 50
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index
                assert_response :forbidden
            end

            grant_privilege(
                context,
                controller: "lesli_shield/roles",
                action: "index"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :index
                assert_response :success

                get :show, params: { id: role.id }
                assert_response :forbidden

                post :create, params: {
                    role: { name: "Forbidden create", permission_level: 10 }
                }
                assert_response :forbidden

                patch :update, params: {
                    id: role.id,
                    role: { name: "Forbidden update" }
                }
                assert_response :forbidden

                delete :destroy, params: { id: role.id }
                assert_response :forbidden

                post :deploy, params: { id: role.id }
                assert_response :forbidden
            end


            refute context.fetch(:account).roles.exists?(name: "Forbidden create")
            assert_equal "Visible with show privilege", role.reload.name
            assert context.fetch(:account).roles.exists?(role.id)

            grant_privilege(
                context,
                controller: "lesli_shield/roles",
                action: "show"
            )

            with_authenticated_request(context.fetch(:user)) do
                get :show, params: { id: role.id }
                assert_response :success
            end
        end
    end
end
