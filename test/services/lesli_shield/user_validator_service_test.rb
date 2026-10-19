require "test_helper"

module LesliShield
    class UserValidatorServiceTest < ActiveSupport::TestCase
        class UserWithoutAudit
            attr_reader :logged_payload

            def active?
                false
            end

            def locked_until
                nil
            end

            def log(**payload)
                @logged_payload = payload
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

        test "records validation failures through the optional log API" do
            user = UserWithoutAudit.new
            service = LesliShield::UserValidatorService.new(user)

            refute service.send(:active?)
            refute user.respond_to?(:logs)
            assert_equal ["user_locked"], service.errors
            assert_equal({
                engine: LesliShield,
                source: "LesliShield::UserValidatorService",
                action: "validate",
                operation: "session_creation_failed",
                description: "user_locked"
            }, user.logged_payload)
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
