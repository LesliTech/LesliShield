require "test_helper"

class Users::SessionsControllerTest < ActionController::TestCase
    tests Users::SessionsController

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

    FailureUser = Struct.new(:account, :logs) do
        def log(**attributes)
            logs << attributes
        end
    end

    FakeValidator = Struct.new(:message) do
        def validate
            self
        end

        def valid?
            false
        end

        def errors_as_sentence
            message
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
        assert_equal "/dashboard?tab=activity", safe_redirect_path("/dashboard?tab=activity")
    end

    test "accepts an absolute URL on the current host" do
        redirect_url = "https://test.host/dashboard"

        assert_equal redirect_url, safe_redirect_path(redirect_url)
    end

    test "rejects an external URL" do
        assert_equal "/fallback", safe_redirect_path("https://example.com/dashboard")
    end

    test "rejects a protocol relative URL" do
        assert_equal "/fallback", safe_redirect_path("//example.com/dashboard")
    end

    test "rejects a path without a leading slash" do
        assert_equal "/fallback", safe_redirect_path("dashboard")
    end

    test "rejects an invalid URI" do
        assert_equal "/fallback", safe_redirect_path("http://[invalid")
    end

    test "records success only after Devise signs the user in" do
        events = []
        logs = []
        user = FakeUser.new(events, nil, logs)
        service = FakeSessionService.new(events, { id: 42 })

        stub_session_dependencies(service, events) do
            create_authenticated_session(user)
        end

        assert_equal %i[session_created signed_in success_logged], events
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
        service = FakeSessionService.new(events, { id: 42 })

        raised = assert_raises(StandardError) do
            stub_session_dependencies(service, events) do
                create_authenticated_session(user)
            end
        end

        assert_same error, raised
        assert_equal %i[session_created signed_in success_logged signed_out], events
        assert_nil session[:user_session_id]
    end

    test "records one failed event when user validation rejects the login" do
        logs = []
        user = FailureUser.new(Object.new, logs)
        validator = FakeValidator.new("User is locked")
        warden = Struct.new(:user, :options) do
            def authenticate(options)
                self.options = options
                user
            end
        end.new(user)

        replace_singleton_method(@controller, :resource_name, -> { :user }) do
            replace_singleton_method(@controller, :warden, -> { warden }) do
                replace_singleton_method(LesliShield::UserValidatorService, :new, ->(*) { validator }) do
                    replace_singleton_method(@controller, :danger, ->(*) {}) do
                        replace_singleton_method(@controller, :redirect_to, ->(*) { true }) do
                            replace_singleton_method(@controller, :user_session_path, ->(*) { "/login" }) do
                                replace_singleton_method(@controller, :sign_in_params, -> { { redirect: nil } }) do
                                    replace_singleton_method(@controller, :action_name, -> { "create" }) do
                                        @controller.create
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        assert_equal({
            engine: LesliShield,
            source: "Users::SessionsController",
            action: "create",
            operation: "session_creation_failed",
            description: "User is locked"
        }, logs.sole)
        assert_equal false, warden.options[:store]
    end

    private

    def safe_redirect_path(value)
        @controller.send(:safe_redirect_path, value)
    end

    def create_authenticated_session(user)
        @controller.send(:create_authenticated_session!, user, {})
    end

    def stub_session_dependencies(service, events, &block)
        transaction = ->(&transaction_block) { transaction_block.call }
        sign_in = ->(*) { events << :signed_in }
        sign_out = ->(*) { events << :signed_out }

        replace_singleton_method(Lesli::User, :transaction, transaction) do
            replace_singleton_method(LesliShield::UserSessionService, :new, ->(*) { service }) do
                replace_singleton_method(@controller, :resource_name, -> { :user }) do
                    replace_singleton_method(@controller, :action_name, -> { "create" }) do
                        replace_singleton_method(@controller, :sign_in, sign_in) do
                            replace_singleton_method(@controller, :sign_out, sign_out, &block)
                        end
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
