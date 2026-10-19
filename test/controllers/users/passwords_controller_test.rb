require "test_helper"

class Users::PasswordsControllerTest < ActionController::TestCase
    tests Users::PasswordsController

    SessionRecord = Struct.new(:id)

    FakeSessionService = Struct.new(:session_record) do
        def create(*)
            self
        end

        def result
            session_record
        end
    end

    FakeUser = Struct.new(:logs) do
        def account
            true
        end

        def log(**attributes)
            logs << attributes
        end
    end

    setup do
        @request.host = "test.host"
    end

    test "normalizes and protects password reset email rate-limit identities" do
        first_key = email_rate_limit_key(" User@Example.COM ")
        second_key = email_rate_limit_key("user@example.com")
        different_key = email_rate_limit_key("other@example.com")

        assert_equal first_key, second_key
        refute_equal first_key, different_key
        assert_match(/\A\h{64}\z/, first_key)
        refute_includes first_key, "user@example.com"
    end

    test "records one successful audit event with the application session" do
        logs = []
        user = FakeUser.new(logs)
        service = FakeSessionService.new(SessionRecord.new(42))
        fake_resource_class = Class.new

        transaction = ->(&transaction_block) { transaction_block.call }

        replace_singleton_method(
            @controller,
            :resource_class,
            -> { fake_resource_class }
        ) do
            replace_singleton_method(fake_resource_class, :transaction, transaction) do
                replace_singleton_method(
                    LesliShield::UserSessionService,
                    :new,
                    ->(*) { service }
                ) do
                    replace_singleton_method(
                        @controller,
                        :action_name,
                        -> { "update" }
                    ) do
                        application_session_id = @controller.send(
                            :create_application_session_and_audit!,
                            user
                        )

                        assert_equal 42, application_session_id
                    end
                end
            end
        end

        assert_equal({
            engine: LesliShield,
            source: "Users::PasswordsController",
            action: "update",
            operation: "password_reset_succeeded",
            description: "Password reset successful",
            session_id: 42
        }, logs.sole)
    end

    private

    def email_rate_limit_key(email)
        @controller.params = ActionController::Parameters.new(
            user: { email: email }
        )
        replace_singleton_method(@controller, :resource_name, -> { :user }) do
            return @controller.send(:password_reset_email_rate_limit_key)
        end
    end

    def replace_singleton_method(object, method_name, replacement)
        singleton_class = object.singleton_class
        locally_defined = singleton_class.instance_methods(false).include?(method_name)
        original_method = singleton_class.instance_method(method_name) if locally_defined

        singleton_class.define_method(method_name, &replacement)
        yield
    ensure
        if locally_defined
            singleton_class.define_method(method_name, original_method)
        elsif singleton_class.method_defined?(method_name)
            singleton_class.remove_method(method_name)
        end
    end
end
