require "test_helper"

class LesliShieldTest < ActiveSupport::TestCase
    test "it has a version number" do
        assert LesliShield::VERSION
    end
    test "it has a build number" do
        assert LesliShield::BUILD
    end
end
