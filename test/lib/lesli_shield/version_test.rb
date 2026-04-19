require "test_helper"

module LesliShield
    class VersionTest < ActiveSupport::TestCase
        test "it has a version number" do
            assert LesliShield::VERSION
        end
        test "it has a build number" do
            assert LesliShield::BUILD
        end

        # def test_version_constant_exists
        #     assert defined?(LesliShield::VERSION)
        # end

        # def test_build_constant_exists
        #     assert defined?(LesliShield::BUILD)
        # end

        # def test_version_value
        #     assert_equal "1.1.0", LesliShield::VERSION
        # end

        # def test_build_value
        #     assert_equal "1775525290", LesliShield::BUILD
        # end
    end
end
