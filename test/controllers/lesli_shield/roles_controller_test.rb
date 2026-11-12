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
                post :create, params: {
                    role: { name: "Elevated role", permission_level: 101 }
                }
                assert_response :unprocessable_content

                patch :update, params: {
                    id: role.id,
                    role: { permission_level: 101 }
                }
                assert_response :unprocessable_content
            end

            refute context.fetch(:account).roles.exists?(name: "Elevated role")
            assert_equal 50, role.reload.permission_level
        end

        test "uses the role service for the successful mutation lifecycle" do
            context = insert_account_context("role-mutation-lifecycle")

            with_authorized_request(context.fetch(:user)) do
                post :create, params: {
                    role: {
                        name: "  Lifecycle   role ",
                        description: "  Initial   description ",
                        permission_level: 20
                    }
                }
                assert_response :see_other

                role = context.fetch(:account).roles.find_by!(
                    name: "Lifecycle role"
                )
                assert_equal "Initial description", role.description

                patch :update, params: {
                    id: role.id,
                    role: { name: "Updated lifecycle role" }
                }
                assert_response :see_other
                assert_equal "Updated lifecycle role", role.reload.name

                delete :destroy, params: { id: role.id }
                assert_response :see_other
                refute context.fetch(:account).roles.exists?(role.id)
            end
        end

        test "deploys the saved selection through the explicit action" do
            context = insert_account_context("role-explicit-deploy")
            role = insert_role(
                context,
                name: "Explicit deployment role",
                permission_level: 50
            )
            role_action = insert_role_action(role, label: "Deployable action")

            with_authorized_request(context.fetch(:user)) do
                post :deploy,
                    params: { id: role.id },
                    format: :turbo_stream

                assert_response :see_other
            end

            assert Role::Privilege.exists?(
                role: role,
                controller: role_action.action.parent.route,
                action: role_action.action.action,
                active: true
            )
            assert_not_nil role.reload.deployed_at
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

                post :duplicate, params: { id: role.id }
                assert_response :forbidden
            end
        end

        test "renders every creation field directly with a required numeric level" do
            context = insert_account_context("role-new-form")

            with_authorized_request(context.fetch(:user)) do
                get :new

                assert_response :success
                assert_select "form[action='#{roles_path}']" do
                    assert_select "h2", count: 0
                    assert_select "input[name='role[name]']"
                    assert_select "textarea[name='role[description]']"
                    assert_select "input[name='role[active]'][type='radio']", count: 2
                    assert_select "input[name='role[permission_level]'][type='number'][required]"
                    assert_select "input[name='role[path_default]']"
                    assert_select "details", count: 0
                    assert_select "input[name='role[authorization_level]']", count: 0
                    assert_select "input[name='role[exact_permission_level]']", count: 0
                    assert_select "input[name='role[isolated]']", count: 0
                    assert_select "input[name='role[path_limited]']", count: 0
                    assert_select "input[type='submit'][data-turbo-submits-with]",
                        value: I18n.t("lesli_shield.roles.action_create")
                end
            end
        end

        test "renders validation errors inline and preserves the numeric level" do
            context = insert_account_context("role-inline-errors")

            with_authorized_request(context.fetch(:user)) do
                post :create, params: {
                    role: {
                        name: "",
                        permission_level: 101
                    }
                }

                assert_response :unprocessable_content
                assert_select "#role-form [role='alert']"
                assert_select "input[name='role[permission_level]'][value='101']"
                assert_select "p.text-red-600", minimum: 1
            end
        end

        test "rejects role creation when the authorization level is missing" do
            context = insert_account_context("role-missing-level")

            with_authorized_request(context.fetch(:user)) do
                post :create, params: {
                    role: {
                        name: "Role without level",
                        permission_level: ""
                    }
                }

                assert_response :unprocessable_content
                assert_select "input[name='role[permission_level]'][value='']"
                assert_select "#role-form [role='alert']"
            end

            refute context.fetch(:account).roles.exists?(name: "Role without level")
        end

        test "renders role detail summaries navigation and safe status controls" do
            context = insert_account_context("role-detail-interface")
            role = insert_role(
                context,
                name: "Operations role",
                permission_level: 50
            )
            assign_role(context.fetch(:user), role)
            insert_role_action(role, label: "Detail permission")

            with_authorized_request(context.fetch(:user)) do
                get :show, params: { id: role.id }

                assert_response :success
                assert_select "#role-detail-content"
                assert_select "nav a[href='#{role_path(role, anchor: "general")}']", count: 0
                assert_select "#members", text: /1/
                assert_select "#members #role-status-title", count: 1
                assert_select "section[aria-labelledby='role-status-title']", count: 0
                assert_select "#activity", count: 0
                assert_select "a[href='#{role_actions_path(role)}']"
                assert_select "a[href='#{users_path}']"
                assert_select "form[action='#{duplicate_role_path(role)}']"
                assert_select "#role-form-fields button[name='role[active]'][value='false']"
                assert_select "#role-detail-content.w-full"
                assert_select "#general input[name='role[permission_level]'][type='number']"
                assert_select "#general input[name='role[path_default]']"
                assert_select "#general details", count: 0
                assert_select "#general input[type='submit'][data-turbo-submits-with]",
                    value: I18n.t("lesli_shield.roles.action_update")
                assert_select "button[type='submit'][form='role-form-fields']", count: 0
                assert_select "[data-turbo-confirm]"
                assert_select "input[name='role[isolated]']", count: 0
                assert_select "input[name='role[path_limited]']", count: 0
            end
        end

        test "duplicates a role as an inactive copy and redirects to its detail" do
            context = insert_account_context("role-controller-duplicate")
            role = insert_role(
                context,
                name: "Source role",
                permission_level: 40
            )
            insert_role_action(role, label: "Copied permission")

            with_authorized_request(context.fetch(:user)) do
                post :duplicate, params: { id: role.id }

                duplicate = context.fetch(:account).roles.find_by!(
                    name: "Source role copy"
                )
                assert_response :see_other
                assert_redirected_to role_path(duplicate)
                refute_predicate duplicate, :active?
                assert_equal 1, duplicate.actions.count
            end
        end

        test "renders the responsive role administration interface with filters" do
            context = insert_account_context("roles-index-interface")
            system_role = insert_role(
                context,
                name: "Admin",
                permission_level: 90,
                system_name: "admin"
            )
            insert_role(
                context,
                name: "Support team",
                permission_level: 30
            )

            with_authorized_request(context.fetch(:user)) do
                get :index, params: {
                    search: "admin",
                    status: "active",
                    type: "system"
                }

                assert_response :success
                assert_select "h1", text: I18n.t("lesli_shield.roles.title")
                assert_select "a[href='#{new_role_path}']",
                    text: /#{Regexp.escape(I18n.t("lesli_shield.roles.action_create"))}/
                assert_select "input[name='search'][value='admin']"
                assert_select "select[name='status'] option[value='active'][selected]"
                assert_select "select[name='type'] option[value='system'][selected]"
                assert_select "tbody tr", count: 1
                assert_select "tbody tr a[data-turbo-frame='_top']",
                    text: system_role.name
                assert_select ".md\\:hidden article", count: 1
                assert_select "[data-turbo-submits-with]"
            end
        end
    end
end
