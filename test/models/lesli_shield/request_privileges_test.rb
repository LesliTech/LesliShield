require "test_helper"
require_relative "../../support/role_security_test_helpers"

module LesliShield
    class RequestPrivilegesTest < ActiveSupport::TestCase
        include RoleSecurityTestHelpers

        test "queries privileges once per request and reloads them on the next request" do
            context = insert_account_context("request-privileges")
            user = context.fetch(:user)
            grant_privilege(context, controller: "profiles", action: "show")
            queries = []
            subscriber = ->(*args) do
                payload = args.last
                queries << payload[:sql] if payload[:sql].include?("lesli_shield_role_privileges") &&
                    payload[:sql].start_with?("SELECT")
            end
            ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
                user.with_privileges do
                    assert user.has_privileges_for?("profiles", "show")
                    refute user.has_privileges_for?("profiles", "update")
                    assert user.has_privileges_for?("profiles", "show")
                end
            end
            assert_equal 1, queries.size

            context.fetch(:manager_role).update!(active: false)
            user.with_privileges do
                refute user.has_privileges_for?("profiles", "show")
            end
        end

        test "clears the request cache when an exception interrupts rendering" do
            context = insert_account_context("request-error")
            user = context.fetch(:user)
            grant_privilege(context, controller: "profiles", action: "show")
            assert_raises(RuntimeError) do
                user.with_privileges do
                    assert user.has_privileges_for?("profiles", "show")
                    raise "render failed"
                end
            end
            context.fetch(:manager_role).update!(active: false)
            refute user.has_privileges_for?("profiles", "show")
        end
    end
end
