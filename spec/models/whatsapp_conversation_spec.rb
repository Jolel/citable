# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhatsappConversation, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:customer).optional }
    it { is_expected.to belong_to(:service).optional }
    it { is_expected.to belong_to(:booking).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:from_phone) }
    it { is_expected.to validate_presence_of(:step) }
  end

  describe ".active" do
    it "excludes expired conversations" do
      active = create(:whatsapp_conversation, updated_at: 29.minutes.ago)
      create(:whatsapp_conversation, updated_at: 31.minutes.ago)

      expect(described_class.active).to contain_exactly(active)
    end
  end
end
