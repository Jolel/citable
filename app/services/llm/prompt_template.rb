# frozen_string_literal: true

module Llm
  # Loads versioned YAML+ERB prompt files from config/prompts/.
  #
  # File naming: config/prompts/<name>.<locale>.<version>.yml
  #   e.g. config/prompts/booking_slot_extractor.es-MX.v1.yml
  #
  # Active version per template is resolved (in priority order) from:
  #   1. Rails.application.credentials.dig(:nlu, :prompt_versions, name.to_sym)
  #   2. Hardcoded default "v1"
  #
  # YAML structure expected: { "system" => "..." }
  # ERB is rendered first so dynamic values (dates, service lists) can be
  # injected via the +vars:+ hash — each key becomes a method in the binding.
  #
  # Returns: { system: String, version: String }
  module PromptTemplate
    DEFAULT_VERSION = "v1"
    DEFAULT_LOCALE  = :"es-MX"

    # @param name    [String]  template name (matches file prefix)
    # @param vars    [Hash]    ERB variables — symbols or strings as keys
    # @param version [String, nil]  override; nil = credentials or "v1"
    # @param locale  [Symbol, String]
    # @return [Hash{system: String, version: String}]
    def self.render(name:, vars: {}, version: nil, locale: DEFAULT_LOCALE)
      version = resolve_version(name, version)
      path    = template_path(name, locale, version)

      raise ArgumentError, "Prompt template not found: #{path}" unless File.exist?(path)

      ctx     = TemplateContext.new(vars)
      content = ERB.new(File.read(path), trim_mode: "-").result(ctx.get_binding)
      data    = YAML.safe_load(content, permitted_classes: []) || {}

      { system: data["system"].to_s.strip, version: version }
    end

    def self.resolve_version(name, override)
      override.presence ||
        Rails.application.credentials.dig(:nlu, :prompt_versions, name.to_sym).presence ||
        DEFAULT_VERSION
    end
    private_class_method :resolve_version

    def self.template_path(name, locale, version)
      Rails.root.join("config", "prompts", "#{name}.#{locale}.#{version}.yml")
    end
    private_class_method :template_path

    # Provides a clean ERB binding where each key from +vars+ is accessible
    # as a method (and an instance variable) within the template.
    class TemplateContext
      def initialize(vars)
        vars.each do |k, v|
          instance_variable_set(:"@#{k}", v)
          define_singleton_method(k) { v }
        end
      end

      def get_binding = binding
    end
    private_constant :TemplateContext
  end
end
