# frozen_string_literal: true

require "dry/container/stub"

# Enable Citable::Container.stub for use inside individual examples that
# resolve dependencies from the container directly (rather than via explicit
# constructor injection). The pilot LLM specs use explicit instance_double
# injection and don't need this — but it's the standard hook that future
# integrations (Twilio, Resend, …) will rely on.
RSpec.configure do |config|
  config.before(:suite) do
    Citable::Container.enable_stubs!
  end

  config.after(:each) do
    Citable::Container.unstub if Citable::Container.respond_to?(:unstub)
  end
end
