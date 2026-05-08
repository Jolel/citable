# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ScopeClassifier do
  include Dry::Monads[:result]

  let(:account) { build_stubbed(:account) }
  let(:llm)     { instance_double(Llm::Port) }

  def stub_llm(intent:, confidence: 0.90)
    allow(llm).to receive(:call).and_return(
      Llm::Response.new(
        content: { "intent" => intent, "confidence" => confidence },
        input_tokens: 60, output_tokens: 8, model: "test-model"
      )
    )
  end

  Llm::ScopeClassifier::OUT_OF_SCOPE_TYPES.each do |type|
    context "when LLM returns '#{type}' with high confidence" do
      before { stub_llm(intent: type) }

      it "returns Success with intent :#{type}" do
        result = described_class.call(body: "¿aceptan tarjeta?", account: account, llm: llm)

        expect(result).to be_success
        expect(result.value![:intent]).to eq(type.to_sym)
        expect(result.value![:input_tokens]).to eq(60)
      end
    end
  end

  context "when LLM returns 'other'" do
    before { stub_llm(intent: "other") }

    it "returns Failure(:not_out_of_scope)" do
      result = described_class.call(body: "quiero reservar", account: account, llm: llm)
      expect(result).to be_failure.and(have_attributes(failure: :not_out_of_scope))
    end
  end

  context "when confidence is below the threshold" do
    before { stub_llm(intent: "payment_question", confidence: 0.50) }

    it "returns Failure(:not_out_of_scope)" do
      result = described_class.call(body: "¿algo?", account: account, llm: llm)
      expect(result).to be_failure.and(have_attributes(failure: :not_out_of_scope))
    end
  end

  context "when the LLM raises an error" do
    before do
      allow(llm).to receive(:call).and_raise(Llm::Port::Error, "timeout")
    end

    it "returns Failure(:llm_error)" do
      result = described_class.call(body: "¿aceptan tarjeta?", account: account, llm: llm)
      expect(result).to be_failure.and(have_attributes(failure: :llm_error))
    end
  end
end
