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

                post :create, params: {
                    role_id: role.id,
                    action_id: 1
                }
                assert_response :forbidden

                delete :destroy, params: { role_id: role.id, id: 1 }
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

                post :create, params: {
                    role_id: role.id,
                    action_id: 1
                }
                assert_response :forbidden

                delete :destroy, params: { role_id: role.id, id: 1 }
                assert_response :forbidden
            end
        end

        test "updates one permission per request without deploying the role" do
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
                post :create,
                    params: {
                        role_id: role.id,
                        action_id: next_selection.action_id
                    },
                    format: :turbo_stream

                assert_response :success
                assert_select "turbo-stream[action='replace']" \
                    "[target='shield-role-permissions']",
                    count: 1
                assert_select "turbo-stream[action='replace']" \
                    "[target='role-permission-deployment-status']",
                    count: 1
                assert_includes response.body,
                    I18n.t("lesli_shield.roles.deployment_statuses.pending")
            end

            assert_nil previous_selection.reload.deleted_at
            assert_nil next_selection.reload.deleted_at
            assert_not_nil role.reload.modified_at
            assert_equal deployed_at.to_i, role.deployed_at.to_i
            assert_equal cached_privilege, role.privileges.find(cached_privilege.id)

            with_authorized_request(context.fetch(:user)) do
                delete :destroy,
                    params: {
                        role_id: role.id,
                        id: previous_selection.action_id
                    },
                    format: :json

                assert_response :success
            end

            assert_not_nil previous_selection.reload.deleted_at
            assert_nil next_selection.reload.deleted_at
        end

        test "shows CRUD and custom actions together for every engine" do
            context = insert_account_context("all-permissions")
            role = insert_role(context, name: "All permissions", permission_level: 50)
            standard = insert_role_action(role, label: "Invitations")
            custom = standard.action.parent.children.create!(
                action: "resend", identifier: "resend", label: "Resend invitation"
            )
            other = insert_role_action(role, label: "Other engine")
            other.action.parent.update!(engine: "lesli_audit")

            with_authorized_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id }

                assert_response :success
                assert_select "section[id^='permission-engine-']", count: 2
                assert_select "#permission-engine-shield table", count: 1
                assert_select "#permission-engine-shield table + [data-custom-actions]" do
                    assert_select "input[name='action_id'][value='#{custom.id}']", count: 1
                end
                assert_select "form[action='#{role_action_path(role, standard.action_id)}']" do
                    assert_select "input[name='_method'][value='delete']", count: 1
                end
                assert_select "a[href='#{role_actions_path(role)}'][aria-current='page']", count: 1
                assert_select "form[action='#{deploy_role_path(role)}']", count: 1
            end
        end

        test "filters by engine and keeps the complete navigation during search" do
            context = insert_account_context("engine-permissions")
            role = insert_role(context, name: "Engine permissions", permission_level: 50)
            standard = insert_role_action(role, label: "Invitations")
            standard.action.parent.update!(engine: "lesli_shield")
            custom = standard.action.parent.children.create!(
                action: "resend", identifier: "resend", label: "Resend invitation"
            )
            other = insert_role_action(role, label: "Other engine")
            other.action.parent.update!(engine: "lesli_audit")

            with_authorized_request(context.fetch(:user)) do
                get :index, params: { role_id: role.id, engine_slug: "lesli-shield" }

                assert_response :success
                assert_select "section[id^='permission-engine-']", count: 1
                assert_select "#permission-engine-lesli_shield table", count: 1
                assert_select "input[name='action_id'][value='#{custom.id}']", count: 1
                assert_select "a[href='#{engine_role_actions_path(role, engine_slug: "lesli-shield")}'][aria-current='page'][data-turbo-frame='_top']", count: 1
                assert_select "a[href='#{engine_role_actions_path(role, engine_slug: "lesli-audit")}']", count: 1
                assert_select "form[action='#{engine_role_actions_path(role, engine_slug: "lesli-shield")}'][method='get'][data-turbo-frame='_top']", count: 1

                get :index, params: {
                    role_id: role.id, engine_slug: "lesli-shield", search: "resend"
                }
                assert_response :success
                assert_select "table", count: 0
                assert_select "[data-custom-actions]", count: 1

                get :index, params: {
                    role_id: role.id, engine_slug: "lesli-shield", search: "no-match"
                }
                assert_response :success
                assert_select "section[id^='permission-engine-']", count: 0
                assert_select "a[aria-current='page']", text: /LesliShield/
                assert_select "a[href='#{engine_role_actions_path(role, engine_slug: "lesli-audit", search: "no-match")}']", count: 1
                assert_includes response.body, I18n.t("lesli_shield.roles.permissions.no_matches")
            end
        end

        test "preserves engine and search through POST and DELETE with HTML and Turbo" do
            context = insert_account_context("engine-toggle")
            role = insert_role(context, name: "Engine toggle", permission_level: 50)
            standard = insert_role_action(role, label: "Invitations")
            custom = standard.action.parent.children.create!(
                action: "resend", identifier: "resend", label: "Resend invitation"
            )

            with_authorized_request(context.fetch(:user)) do
                post :create, params: {
                    role_id: role.id, action_id: custom.id,
                    engine_slug: "shield", search: "resend"
                }
                assert_redirected_to engine_role_actions_path(role, engine_slug: "shield", search: "resend")
                assert role.actions.exists?(action_id: custom.id)

                delete :destroy, params: {
                    role_id: role.id, id: custom.id,
                    engine_slug: "shield", search: "resend"
                }, format: :turbo_stream

                assert_response :success
                refute role.actions.exists?(action_id: custom.id)
                assert_select "turbo-stream[target='shield-role-permissions']", count: 1
                assert_includes response.body, "engine_slug=shield"
                assert_includes response.body, "search=resend"
                assert_includes response.body, "Resend invitation"
            end
        end

        test "rejects unknown engine slugs before changing a permission" do
            context = insert_account_context("unknown-engine")
            role = insert_role(context, name: "Unknown engine", permission_level: 50)
            selected = insert_role_action(role, label: "Selection")

            with_authorized_request(context.fetch(:user)) do
                assert_raises(ActiveRecord::RecordNotFound) do
                    get :index, params: { role_id: role.id, engine_slug: "unknown" }
                end
                assert_raises(ActiveRecord::RecordNotFound) do
                    delete :destroy, params: {
                        role_id: role.id, id: selected.action_id, engine_slug: "unknown"
                    }
                end
            end

            assert_nil selected.reload.deleted_at
        end

        test "loads the complete catalog only when a mutation renders Turbo HTML" do
            context = insert_account_context("permission-catalog-queries")
            role = insert_role(context, name: "Catalog queries", permission_level: 50)
            selection = insert_role_action(role, label: "Selection")
            catalog_queries = []
            track_catalog = lambda do |event|
                sql = event.payload[:sql]
                catalog_queries << sql if sql.include?("LEFT JOIN lesli_shield_role_actions selected_actions")
            end

            ActiveSupport::Notifications.subscribed(track_catalog, "sql.active_record") do
                with_authorized_request(context.fetch(:user)) do
                    [:html, :json, :turbo_stream].each do |format|
                        post :create, params: {
                            role_id: role.id,
                            action_id: selection.action_id,
                            engine_slug: "shield"
                        }, format: format

                        assert_response(format == :html ? :see_other : :success)
                        assert_equal(format == :turbo_stream ? 1 : 0, catalog_queries.size)
                    end
                end
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
                post :create,
                    params: {
                        role_id: role.id,
                        action_id: selection.action.parent_id
                    },
                    format: :turbo_stream

                assert_response :unprocessable_content
            end

            assert_nil selection.reload.deleted_at
            assert_nil role.reload.modified_at
        end

        test "exposes create and destroy routes for permission toggles" do
            @routes = LesliShield::Engine.routes
            action_routes = LesliShield::Engine.routes.routes.select do |route|
                route.defaults[:controller] == "lesli_shield/role/actions"
            end
            assert_equal 4, action_routes.length
            assert_recognizes(
                { controller: "lesli_shield/role/actions", action: "index",
                  role_id: "2", engine_slug: "lesli-shield" },
                { path: "/roles/2/actions/lesli-shield", method: :get }
            )
            assert_recognizes(
                { controller: "lesli_shield/role/actions", action: "create", role_id: "2" },
                { path: "/roles/2/actions", method: :post }
            )
            assert_recognizes(
                { controller: "lesli_shield/role/actions", action: "destroy",
                  role_id: "2", id: "42" },
                { path: "/roles/2/actions/42", method: :delete }
            )
        end

        test "does not expose routes for the unimplemented privileges controller" do
            privilege_routes = LesliShield::Engine.routes.routes.select do |route|
                route.defaults[:controller] == "lesli_shield/role/privileges"
            end

            assert_empty privilege_routes
        end
    end
end
