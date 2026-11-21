require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class UserRolesControllerTest < ActionController::TestCase
        include RoleSecurityTestHelpers
        tests User::RolesController

        test "adds and removes roles in the same frame without duplicate assignments" do
            context = insert_account_context("user-roles")
            role = insert_role(context, name: "Support", permission_level: 50)
            user = context.fetch(:user)

            with_authorized_request(user) do
                get :index, params: { user_id: user.id }
                assert_response :success
                assert_select "form[data-turbo-frame='#{ActionView::RecordIdentifier.dom_id(user, :roles)}']", 1
                assert_select "button[type='submit'][disabled]" do |buttons|
                    assert_equal "!roleId", buttons.first["x-bind:disabled"]
                end
                assert_select "select[name='user_role[role_id]'] option[value='#{role.id}']", 1

                2.times do
                    post :create, params: { user_id: user.id, user_role: { role_id: role.id } }
                    assert_response :see_other
                end
                assert_equal 1, user.user_roles.where(role: role).count

                get :index, params: { user_id: user.id }
                assert_select "select option[value='#{role.id}']", 0
                assert_select "li h4", text: "Support"
                assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(user, :roles)}", 1

                assignment = user.user_roles.find_by!(role: role)
                delete :destroy, params: { user_id: user.id, id: assignment.id }
                assert_response :see_other
                refute user.user_roles.exists?(role: role)
            end
        end

        test "shows inactive roles read only assignments and the empty state" do
            context = insert_account_context("role-presentation")
            user = context.fetch(:user)
            inactive = insert_role(context, name: "Inactive support", permission_level: 50)
            inactive.update_columns(active: false, description: "Handles customer requests")
            assign_role(user, inactive)
            higher = insert_role(context, name: "Protected", permission_level: 101)
            assign_role(user, higher)

            # A separate actor keeps the permission boundary stable.
            actor_context = insert_account_context("role-presentation-actor")
            actor = actor_context.fetch(:user)
            actor.update_columns(account_id: user.account_id)
            assign_role(actor, context.fetch(:manager_role))
            with_authorized_request(actor) do
                get :index, params: { user_id: user.id }
                assert_response :success
                assert_select "li", text: /Inactive support.*Inactive.*Handles customer requests/m
                assert_select "li", text: /Protected.*Read only/m
                assert_select "form[action$='/#{user.user_roles.find_by!(role: higher).id}']", 0

                user.user_roles.destroy_all
                get :index, params: { user_id: user.id }
                assert_select "p", text: I18n.t("lesli_shield.user_roles.empty")
            end
        end

        test "rejects foreign users foreign roles and roles above the actor level" do
            context = insert_account_context("assignment-current")
            other = insert_account_context("assignment-other")
            high = insert_role(context, name: "Higher", permission_level: 101)
            inactive = insert_role(context, name: "Inactive", permission_level: 50)
            inactive.update_columns(active: false)

            with_authorized_request(context.fetch(:user)) do
                assert_raises(ActiveRecord::RecordNotFound) do
                    get :index, params: { user_id: other.fetch(:user).id }
                end
                [high, inactive, other.fetch(:manager_role)].each do |role|
                    assert_raises(ActiveRecord::RecordNotFound) do
                        post :create, params: {
                            user_id: context.fetch(:user).id, user_role: { role_id: role.id }
                        }
                    end
                end
                assignment = assign_role(other.fetch(:user), other.fetch(:manager_role))
                assert_raises(ActiveRecord::RecordNotFound) do
                    delete :destroy, params: { user_id: context.fetch(:user).id, id: assignment.id }
                end
            end
        end
    end
end
