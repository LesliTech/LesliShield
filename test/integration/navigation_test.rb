require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
    test "login renders through the Lesli core controller and layout" do
        get "/login"

        assert_response :success
        assert_select "form.lesli-login-form"
        assert_select "link[href*='sessions.tailwind']"
    end
end
