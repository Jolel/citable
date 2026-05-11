# frozen_string_literal: true

require "rails_helper"

# Shared examples that any concrete Llm::Port adapter must satisfy.
#
# Usage from an adapter spec:
#
#   RSpec.describe Llm::GeminiAdapter do
#     it_behaves_like "an LLM port" do
#       let(:adapter) { described_class.new }
#       let(:stub_success) { ... }
#       let(:stub_failure) { ... }
#     end
#   end
RSpec.shared_examples "an LLM port" do
  let(:schema) do
    { type: "object", properties: { foo: { type: "string" } }, required: [ "foo" ] }
  end

  it "is-a Llm::Port" do
    expect(adapter).to be_a(Llm::Port)
  end

  it "returns an Llm::Response on success" do
    stub_success.call
    result = adapter.call(system: "sys", user: "user", schema: schema)

    expect(result).to be_a(Llm::Response)
    expect(result.content).to be_a(Hash)
    expect(result.input_tokens).to be_a(Integer)
    expect(result.output_tokens).to be_a(Integer)
    expect(result.model).to be_a(String)
  end

  it "raises Llm::Port::Error on transport failure" do
    stub_failure.call
    expect { adapter.call(system: "sys", user: "user", schema: schema) }
      .to raise_error(Llm::Port::Error)
  end
end
