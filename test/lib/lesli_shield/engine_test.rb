require "test_helper"

module LesliShield
    class EngineTest < ActiveSupport::TestCase
        test "engine exists" do
            assert defined?(LesliShield::Engine)
        end

        test "engine inherits from Rails::Engine" do
            assert LesliShield::Engine < Rails::Engine
        end

        test "engine isolates namespace" do
            assert_equal "LesliShield", LesliShield::Engine.railtie_namespace.name
        end
    end
end
