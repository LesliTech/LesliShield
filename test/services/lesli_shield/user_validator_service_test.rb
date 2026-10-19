require "test_helper"

module LesliShield
    class UserValidatorServiceTest < ActiveSupport::TestCase
        class InvalidUser
            def active?
                false
            end

            def confirmed?
                false
            end

            def locked_at
                nil
            end

            def locked_until
                nil
            end

            def roles
                []
            end

            def log(**)
                raise "validation must not emit audit events"
            end
        end

        class ValidUser
            Role = Struct.new(:active)

            def active? = true
            def confirmed? = true
            def locked_at = nil
            def locked_until = nil
            def roles = [Role.new(true)]

            def log(**)
                raise "a valid user must not emit a failure event"
            end
        end

        test "collects validation failures without emitting audit events" do
            service = LesliShield::UserValidatorService.new(InvalidUser.new)

            assert_same service, service.validate
            assert_equal [
                "user_locked",
                "email_not_confirmed",
                "user_has_no_assigned_role"
            ], service.errors
            refute service.valid?
        end

        test "accepts an active unlocked confirmed user with an active role" do
            service = LesliShield::UserValidatorService.new(ValidUser.new)

            assert_same service, service.validate
            assert service.valid?
            assert_empty service.errors
        end

        test "requires a user" do
            error = assert_raises(ArgumentError) do
                LesliShield::UserValidatorService.new(nil)
            end

            assert_equal "user is required", error.message
        end
    end
end
