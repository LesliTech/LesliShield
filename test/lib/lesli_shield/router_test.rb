# frozen_string_literal: true

require "test_helper"

module LesliShield
    class RouterTest < ActiveSupport::TestCase
        test "mounts invitation and Devise routes below a configurable prefix" do
            routes = ActionDispatch::Routing::RouteSet.new

            routes.draw do
                LesliShield::Router.mount_login_at(self, "secure-access")
            end

            helpers = routes.url_helpers
            assert_equal "/secure-access/invitation",
                helpers.user_invitation_path
            assert_equal "/secure-access/login",
                helpers.new_user_session_path

            show_route = routes.recognize_path(
                "/secure-access/invitation",
                method: :get
            )
            update_route = routes.recognize_path(
                "/secure-access/invitation",
                method: :patch
            )

            assert_equal "users/invitations", show_route.fetch(:controller)
            assert_equal "show", show_route.fetch(:action)
            assert_equal "users/invitations", update_route.fetch(:controller)
            assert_equal "update", update_route.fetch(:action)
        end
    end
end
