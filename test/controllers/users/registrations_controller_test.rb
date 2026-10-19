require "test_helper"

class Users::RegistrationsControllerTest < ActionController::TestCase
    tests Users::RegistrationsController

    setup do
        @request.host = "test.host"
    end

    test "normalizes and protects registration email rate-limit identities" do
        first_key = email_rate_limit_key(" User@Example.COM ")
        second_key = email_rate_limit_key("user@example.com")
        different_key = email_rate_limit_key("other@example.com")

        assert_equal first_key, second_key
        refute_equal first_key, different_key
        assert_match(/\A\h{64}\z/, first_key)
        refute_includes first_key, "user@example.com"
    end

    test "returns a generic 429 response when the registration limit is exceeded" do
        store = ActiveSupport::Cache::MemoryStore.new
        @request.headers["Accept"] = "application/json"
        @controller.set_response!(@response)
        @controller.params = ActionController::Parameters.new(
            user: { email: "user@example.com" }
        )

        2.times do
            @controller.send(
                :rate_limiting,
                to: 1,
                within: Users::RegistrationsController::REGISTRATION_RATE_LIMIT_WINDOW,
                by: -> { "test-identity" },
                with: :respond_to_registration_rate_limit,
                store: store,
                name: "test",
                scope: "registrations"
            )
        end

        assert_response :too_many_requests
        assert_equal "3600", response.headers["Retry-After"]
        assert_equal(
            I18n.t(
                "lesli_shield.devise/registrations.message_too_many_attempts"
            ),
            response.parsed_body["error"]
        )
    end

    private

    def email_rate_limit_key(email)
        @controller.params = ActionController::Parameters.new(
            user: { email: email }
        )

        replace_singleton_method(@controller, :resource_name, -> { :user }) do
            return @controller.send(:registration_email_rate_limit_key)
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
