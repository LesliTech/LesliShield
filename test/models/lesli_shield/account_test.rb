require "test_helper"

module LesliShield
  class AccountTest < ActiveSupport::TestCase
    test "model exists" do
      assert defined?(LesliShield::Account)
    end

    test "belongs to lesli account" do
      reflection = LesliShield::Account.reflect_on_association(:account)

      assert_not_nil reflection
      assert_equal :belongs_to, reflection.macro
      assert_equal "Lesli::Account", reflection.class_name
    end
  end
end
