require "test_helper"

class Users::SessionsControllerTest < ActionController::TestCase
    tests Users::SessionsController

    SessionRecord = Struct.new(:id)

    FakeSessionService = Struct.new(:events, :session_record) do
        def create(*)
            events << :session_created
            self
        end

        def result
            session_record
        end
    end

    FakeUser = Struct.new(:events, :log_error, :logs) do
        def log(**attributes)
            events << :success_logged
            logs << attributes if logs
            raise log_error if log_error
        end
    end

    setup do
        @request.host = "test.host"
        @original_path_after_login = Lesli.config.shield[:path_after_login]
        Lesli.config.shield[:path_after_login] = "/fallback"
    end

    teardown do
        Lesli.config.shield[:path_after_login] = @original_path_after_login
    end

    test "accepts a local absolute path" do
        assert_equal "/dashboard?tab=activity", sign_in_path("/dashboard?tab=activity")
    end

    test "accepts an absolute URL on the current host" do
        redirect_url = "https://test.host/dashboard"

        assert_equal redirect_url, sign_in_path(redirect_url)
    end

    test "rejects an external URL" do
        assert_equal "/fallback", sign_in_path("https://example.com/dashboard")
    end

    test "rejects a protocol relative URL" do
        assert_equal "/fallback", sign_in_path("//example.com/dashboard")
    end

    test "rejects a path without a leading slash" do
        assert_equal "/fallback", sign_in_path("dashboard")
    end

    test "rejects an invalid URI" do
        assert_equal "/fallback", sign_in_path("http://[invalid")
    end

    test "normalizes and protects email rate-limit identities" do
        first_key = email_rate_limit_key(" User@Example.COM ")
        second_key = email_rate_limit_key("user@example.com")
        different_key = email_rate_limit_key("other@example.com")

        assert_equal first_key, second_key
        refute_equal first_key, different_key
        assert_match(/\A\h{64}\z/, first_key)
        refute_includes first_key, "user@example.com"
    end

    test "returns a generic 429 response when the login rate limit is exceeded" do
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
                within: Users::SessionsController::LOGIN_RATE_LIMIT_WINDOW,
                by: -> { "test-identity" },
                with: :respond_to_login_rate_limit,
                store: store,
                name: "test",
                scope: "sessions"
            )
        end

        assert_response :too_many_requests
        assert_equal "900", response.headers["Retry-After"]
        assert_equal(
            I18n.t("lesli_shield.devise/sessions.message_too_many_attempts"),
            response.parsed_body["error"]
        )
    end

    test "creates the application session and one successful audit event" do
        events = []
        logs = []
        user = FakeUser.new(events, nil, logs)
        service = FakeSessionService.new(events, SessionRecord.new(42))

        stub_session_dependencies(service, events) do
            persist_application_session(user)
        end

        assert_equal %i[session_created success_logged], events
        assert_equal 42, session[:user_session_id]
        assert_equal({
            engine: LesliShield,
            source: "Users::SessionsController",
            action: "create",
            operation: "session_creation_succeeded",
            description: "Session creation successful",
            session_id: 42
        }, logs.sole)
    end

    test "cleans the Devise session when success logging fails" do
        events = []
        error = StandardError.new("audit unavailable")
        user = FakeUser.new(events, error)
        service = FakeSessionService.new(events, SessionRecord.new(42))

        raised = assert_raises(StandardError) do
            stub_session_dependencies(service, events) do
                persist_application_session(user)
            end
        end

        assert_same error, raised
        assert_equal %i[session_created success_logged signed_out], events
        assert_nil session[:user_session_id]
    end

    private

    def sign_in_path(redirect)
        @controller.params = ActionController::Parameters.new(
            user: { redirect: redirect }
        )
        @controller.send(:after_sign_in_path_for, nil)
    end

    def persist_application_session(user)
        @controller.send(:persist_application_session!, user)
    end

    def email_rate_limit_key(email)
        @controller.params = ActionController::Parameters.new(user: { email: email })
        @controller.send(:login_email_rate_limit_key)
    end

    def stub_session_dependencies(service, events, &block)
        transaction = ->(&transaction_block) { transaction_block.call }
        sign_out = ->(*) { events << :signed_out }

        replace_singleton_method(Lesli::User, :transaction, transaction) do
            replace_singleton_method(LesliShield::UserSessionService, :new, ->(*) { service }) do
                replace_singleton_method(@controller, :resource_name, -> { :user }) do
                    replace_singleton_method(@controller, :action_name, -> { "create" }) do
                        replace_singleton_method(@controller, :sign_out, sign_out, &block)
                    end
                end
            end
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
