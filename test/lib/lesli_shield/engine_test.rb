require "test_helper"

module LesliShield
    class EngineTest < ActiveSupport::TestCase
        test "engine exists" do
            assert defined?(LesliShield::Engine)
        end

        test "engine inherits from Rails::Engine" do
            assert LesliShield::Engine < Rails::Engine
        end

        test "engine isolates namespace" do
            assert_equal "LesliShield", LesliShield::Engine.railtie_namespace.name
        end

        test "engine extends Lesli user with security methods" do
            assert Lesli::User < LesliShield::UserSecurity
        end

        test "enables Devise lockable with a temporary failed-attempt lock" do
            assert_includes Lesli::User.devise_modules, :lockable
            assert_equal :failed_attempts, Devise.lock_strategy
            assert_equal :time, Devise.unlock_strategy
            assert_equal 5, Devise.maximum_attempts
            assert_equal 15.minutes, Devise.unlock_in
            assert Devise.paranoid
        end

        test "locks after five failed authentications and unlocks after the configured window" do
            user = Lesli::User.create!(
                email: "lockable-#{SecureRandom.hex(4)}@example.com",
                password: "Password1!",
                confirmed_at: Time.current
            )

            5.times do
                refute user.valid_for_authentication? { false }
            end

            user.reload
            assert_equal 5, user.failed_attempts
            assert_predicate user, :access_locked?

            user.update_columns(locked_at: 16.minutes.ago)

            assert user.valid_for_authentication? { true }
            assert_equal 0, user.reload.failed_attempts
            assert_nil user.locked_at
        end
    end
end
