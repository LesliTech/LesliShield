# Configure Rails Environment
ENV["RAILS_ENV"] = "test"


# load lesli testing tools
require "lesli_testing"


# register engine for testing
LesliTesting.engine("LesliShield", {
    :coverage_min_coverage => 0.5
})


# Loading dummy app
require_relative "../test/dummy/config/environment"
require "rails/test_help"
