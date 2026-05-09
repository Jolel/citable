# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::PromptTemplate do
  let(:fixtures_dir) { Rails.root.join("spec", "fixtures", "prompts") }

  before do
    FileUtils.mkdir_p(fixtures_dir)
    allow(described_class).to receive(:template_path) { |name, _locale, version|
      fixtures_dir.join("#{name}.es-MX.#{version}.yml")
    }
  end

  after do
    FileUtils.rm_rf(fixtures_dir)
  end

  describe ".render" do
    context "with a simple static template" do
      before do
        File.write(fixtures_dir.join("test_prompt.es-MX.v1.yml"), <<~YAML)
          system: |
            Hola, soy un asistente.
        YAML
      end

      it "returns the system string and version" do
        result = described_class.render(name: "test_prompt")
        expect(result[:system]).to eq("Hola, soy un asistente.")
        expect(result[:version]).to eq("v1")
      end
    end

    context "with ERB variables" do
      before do
        File.write(fixtures_dir.join("dynamic_prompt.es-MX.v1.yml"), <<~YAML)
          system: |
            Hoy es <%= today %> (<%= day_name %>).
        YAML
      end

      it "renders ERB with the provided vars" do
        result = described_class.render(
          name: "dynamic_prompt",
          vars: { today: "2026-05-09", day_name: "sábado" }
        )
        expect(result[:system]).to include("2026-05-09")
        expect(result[:system]).to include("sábado")
      end
    end

    context "with a version override" do
      before do
        File.write(fixtures_dir.join("versioned.es-MX.v2.yml"), <<~YAML)
          system: |
            Versión 2.
        YAML
      end

      it "loads the specified version" do
        result = described_class.render(name: "versioned", version: "v2")
        expect(result[:version]).to eq("v2")
        expect(result[:system]).to include("Versión 2")
      end
    end

    context "when the file does not exist" do
      it "raises ArgumentError" do
        expect {
          described_class.render(name: "nonexistent")
        }.to raise_error(ArgumentError, /not found/)
      end
    end

    context "with the booking_slot_extractor production template" do
      it "loads and renders without error" do
        allow(described_class).to receive(:template_path).and_call_original
        today = Date.new(2026, 5, 9)

        result = described_class.render(
          name: "booking_slot_extractor",
          vars: {
            today_str:    today.strftime("%Y-%m-%d"),
            day_name:     "sábado",
            service_list: "1. Corte, 2. Tinte",
            tomorrow:     (today + 1).strftime("%Y-%m-%d"),
            next_fri:     (today + 6).strftime("%Y-%m-%d"),
            next_sat:     (today + 7).strftime("%Y-%m-%d"),
            next_mon:     (today + 2).strftime("%Y-%m-%d")
          }
        )

        expect(result[:system]).to include("2026-05-09")
        expect(result[:system]).to include("1. Corte, 2. Tinte")
        expect(result[:version]).to eq("v1")
      end
    end
  end
end
