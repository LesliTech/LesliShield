require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
    test "login renders through the Lesli core controller and layout" do
        get "/login"

        assert_response :success
        assert_select "form.lesli-login-form"
        assert_select "link[href*='sessions.tailwind']"
    end

    test "login includes the configured credentials only in demo mode" do
        original_demo_mode = Lesli.config.demo
        Lesli.config.demo = true

        get new_user_session_path

        assert_response :success
        assert_select "fieldset[data-demo-credentials]", count: 1
        assert_select 'input[name="user[email]"]',
            value: Lesli.config.company[:email],
            count: 1
        assert_select 'input[name="user[password]"]',
            value: Lesli.config.security[:password],
            count: 1
    ensure
        Lesli.config.demo = original_demo_mode
    end

    test "login does not expose the configured password outside demo mode" do
        original_demo_mode = Lesli.config.demo
        Lesli.config.demo = false

        get new_user_session_path

        assert_response :success
        assert_select "fieldset[data-demo-credentials]", count: 0
        assert_select 'input[name="user[password]"][value]', count: 0
    ensure
        Lesli.config.demo = original_demo_mode
    end
end
