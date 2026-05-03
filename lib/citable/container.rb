# frozen_string_literal: true

require "dry/container"
require "dry/auto_inject"

module Citable
  class Container
    extend Dry::Container::Mixin

    register("infrastructure.llm", memoize: true) { Llm::GeminiAdapter.new }
  end

  Import = Dry::AutoInject(Container)
end
