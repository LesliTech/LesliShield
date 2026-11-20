require "test_helper"

module Users
    class RegistrationTermsTest < ActionDispatch::IntegrationTest
        setup do
            reset!
            ActionMailer::Base.deliveries.clear
            @original_shield = Lesli.config.shield.dup
            @original_registration = Lesli.config.security[:allow_registration]
            @original_demo = Lesli.config.demo
            Lesli.config.demo = false
            Lesli.config.security[:allow_registration] = true
            Lesli.config.shield.merge!(
                require_terms_acceptance: true,
                terms_url: "/terms",
                terms_version: "terms-v1",
                privacy_url: "/privacy",
                privacy_version: "privacy-v1"
            )
            @email = "legal-#{SecureRandom.hex(6)}@example.com"
        end

        teardown do
            Lesli.config.shield = @original_shield
            Lesli.config.security[:allow_registration] = @original_registration
            Lesli.config.demo = @original_demo
        end

        test "enabled registration renders unchecked acceptance and versioned document links" do
            get new_user_registration_path

            assert_response :success
            assert_select 'input[type="checkbox"][name="user[terms_accepted]"][required]', 1
            assert_select 'input[type="checkbox"][checked]', 0
            assert_select 'a[href="/terms"][target="_blank"]', 1
            assert_select 'a[href="/privacy"][target="_blank"]', 1
            assert_select 'input[name="user[terms_version]"][value="terms-v1"]', 1
            assert_select 'input[name="user[privacy_version]"][value="privacy-v1"]', 1
        end

        test "disabled registration omits the notice and ignores submitted acceptance fields" do
            Lesli.config.shield[:require_terms_acceptance] = false
            get new_user_registration_path
            assert_response :success
            assert_select 'input[name="user[terms_accepted]"]', 0
            assert_select "#registration-privacy-notice", 0

            assert_difference -> { Lesli::User.count }, 1 do
                post user_registration_path, params: { user: attributes.merge(
                    terms_accepted_at: "2000-01-01", legal_acceptance_required: true
                ) }
            end
            assert_response :see_other
            user = Lesli::User.find_by!(email: @email)
            assert_nil user.terms_accepted_at
            assert_nil user.terms_version
            assert_nil user.privacy_version
        end

        test "missing or unchecked acceptance cannot be bypassed with a client flag" do
            [nil, "0", "false"].each do |accepted|
                assert_no_difference -> { Lesli::User.count } do
                    post user_registration_path, params: { user: attributes.merge(
                        terms_accepted: accepted, legal_acceptance_required: false,
                        terms_accepted_at: "2000-01-01"
                    ) }
                end
                assert_response :unprocessable_content
                assert_select "#error_explanation", text: /#{Regexp.escape(I18n.t("lesli_shield.devise_registrations.message_terms_required"))}/
                assert_select 'input[type="checkbox"][checked]', 0
            end
            assert_empty ActionMailer::Base.deliveries
        end

        test "acceptance records server time and preserves Devise confirmation" do
            travel_to Time.utc(2026, 11, 20, 18) do
                assert_difference -> { Lesli::User.count }, 1 do
                    post user_registration_path, params: { user: attributes.merge(terms_accepted_at: "2000-01-01") }
                end
                assert_response :see_other
                user = Lesli::User.find_by!(email: @email)
                assert_equal Time.current, user.terms_accepted_at
                assert_equal "terms-v1", user.terms_version
                assert_equal "privacy-v1", user.privacy_version
                refute user.confirmed?
                assert_equal 1, ActionMailer::Base.deliveries.size
                assert_nil request.session["warden.user.user.key"]
            end
        end

        test "missing and outdated versions require another review" do
            %i[terms_version privacy_version].each do |key|
                [nil, "old-version"].each do |version|
                    # Each submission is independent of the email rate limit.
                    @email = "version-#{SecureRandom.hex(6)}@example.com"
                    assert_no_difference -> { Lesli::User.count } do
                        post user_registration_path, params: { user: attributes.merge(key => version) }
                    end
                    assert_response :unprocessable_content
                    assert_select "#error_explanation", text: /#{Regexp.escape(I18n.t("lesli_shield.devise_registrations.message_legal_documents_changed"))}/
                    assert_select 'input[type="checkbox"][checked]', 0
                    assert_select "input[name='user[#{key}]'][value='#{Lesli.config.shield[key]}']", 1
                end
            end
        end

        test "Turbo errors preserve accepted current versions and clear passwords" do
            assert_no_difference -> { Lesli::User.count } do
                post user_registration_path, params: { user: attributes.merge(password_confirmation: "different") },
                    as: :turbo_stream
            end
            assert_response :unprocessable_content
            assert_select 'input[type="checkbox"][checked]', 1
            assert_select "input[name='user[email]'][value='#{@email}']", 1
            assert_select 'input[type="password"]' do |fields|
                assert fields.all? { |field| field["value"].blank? }
            end
        end

        test "JSON cannot bypass acceptance or change the supported response formats" do
            assert_no_difference -> { Lesli::User.count } do
                post user_registration_path, params: { user: attributes.except(:terms_accepted) }, as: :json
            end
            # Devise's registration controller currently responds to HTML only.
            assert_response :not_acceptable
        end

        test "administrative creation and later updates do not fabricate acceptance" do
            user = Lesli::User.new(attributes.except(:terms_accepted, :terms_version, :privacy_version))
            user.skip_confirmation!
            user.save!
            user.update!(first_name: "Existing")
            assert_nil user.reload.terms_accepted_at
            assert_nil user.terms_version
            assert_nil user.privacy_version
        end

        test "incomplete configuration fails clearly instead of registering empty document versions" do
            Lesli.config.shield[:privacy_version] = nil
            error = assert_raises(ArgumentError) { get new_user_registration_path }
            assert_includes error.message, "config.shield[:privacy_version]"
        end

        private

        def attributes
            { email: @email, password: "password-123", password_confirmation: "password-123",
                terms_accepted: "1", terms_version: "terms-v1", privacy_version: "privacy-v1" }
        end
    end
end
