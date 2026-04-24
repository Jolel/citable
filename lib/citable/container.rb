# frozen_string_literal: true

require "dry/system"

module Citable
  class Container < Dry::System::Container
    configure do |config|
      config.root = Pathname(__dir__).join("../..")

      # Providers live in config/providers/ (e.g. config/providers/twilio.rb)
      config.provider_dirs = ["config/providers"]

      config.component_dirs.add "lib" do |dir|
        # Strip the leading "citable/" path segment from the component key so that
        # lib/citable/container.rb doesn't register itself as "citable.container".
        dir.namespaces.add "citable", key: nil
      end
    end
  end
end
