require "test_helper"

module LesliShield
    class UserValidatorServiceTest < ActiveSupport::TestCase
        Role = Struct.new(:active)

        class RoleCollection
            def initialize(roles)
                @roles = roles
            end

            def exists?(attributes = nil)
                return @roles.any? unless attributes

                @roles.any? do |role|
                    attributes.all? { |name, value| role.public_send(name) == value }
                end
            end
        end

        class InvalidUser
            def account
                nil
            end

            def active?
                false
            end

            def locked_at
                nil
            end

            def locked_until
                nil
            end

            def roles
                RoleCollection.new([])
            end

            def log(**)
                raise "validation must not emit audit events"
            end
        end

        class ValidUser
            def account
                Object.new
            end

            def active?
                true
            end

            def locked_at
                nil
            end

            def locked_until
                nil
            end

            def roles
                RoleCollection.new([Role.new(true)])
            end

            def log(**)
                raise "a valid user must not emit a failure event"
            end
        end

        class UserWithoutActiveRoles < ValidUser
            def roles
                RoleCollection.new([Role.new(false)])
            end
        end

        class TemporarilyLockedUser < ValidUser
            def locked_until
                5.minutes.from_now
            end
        end

        test "collects validation failures without emitting audit events" do
            service = LesliShield::UserValidatorService.new(InvalidUser.new)

            assert_same service, service.validate
            assert_equal [
                "user_has_no_account",
                "user_locked",
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

        test "rejects a user whose assigned roles are inactive" do
            service = LesliShield::UserValidatorService.new(UserWithoutActiveRoles.new)

            assert_same service, service.validate
            assert_equal ["user_has_no_active_role"], service.errors
            refute service.valid?
        end

        test "rejects a user with an active temporary lock" do
            service = LesliShield::UserValidatorService.new(
                TemporarilyLockedUser.new
            )

            assert_same service, service.validate
            assert_equal ["user_locked"], service.errors
            refute service.valid?
        end

        test "requires a user" do
            error = assert_raises(ArgumentError) do
                LesliShield::UserValidatorService.new(nil)
            end

            assert_equal "user is required", error.message
        end
    end
end
