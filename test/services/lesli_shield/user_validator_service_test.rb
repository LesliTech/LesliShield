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

        test "records validation failures through the optional log API" do
            user = UserWithoutAudit.new
            service = LesliShield::UserValidatorService.new
            service.instance_variable_set(:@resource, user)

            refute service.send(:active?)
            refute user.respond_to?(:logs)
            assert_equal({
                engine: LesliShield,
                source: "LesliShield::UserValidatorService",
                action: "validate",
                operation: "session_creation_failed",
                description: "user_locked"
            }, user.logged_payload)
        end
    end
end
