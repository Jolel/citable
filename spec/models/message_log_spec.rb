# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageLog, type: :model do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:booking).optional }
    it { is_expected.to belong_to(:customer).optional }
  end

  describe "validations" do
    subject { build(:message_log) }

    it { is_expected.to validate_presence_of(:body) }

    it "is invalid with unknown channel" do
      expect(build(:message_log, channel: "sms")).not_to be_valid
    end

    it "is invalid with unknown direction" do
      expect(build(:message_log, direction: "sideways")).not_to be_valid
    end

    it "is invalid with unknown status" do
      expect(build(:message_log, status: "bounced")).not_to be_valid
    end

    it "accepts valid channel whatsapp" do
      expect(build(:message_log, channel: "whatsapp")).to be_valid
    end

    it "accepts valid channel email" do
      expect(build(:message_log, :email)).to be_valid
    end
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let(:booking) { create(:booking, account: account, user: create(:user, account: account), service: create(:service, account: account), customer: create(:customer, account: account)) }
    let!(:outbound_whatsapp) { create(:message_log, account: account, booking: booking, customer: booking.customer) }
    let!(:inbound_whatsapp)  { create(:message_log, :inbound, account: account, booking: booking, customer: booking.customer) }
    let!(:outbound_email)    { create(:message_log, :email, account: account, booking: booking, customer: booking.customer) }

    describe ".outbound" do
      it "returns outbound messages" do
        expect(MessageLog.outbound).to include(outbound_whatsapp, outbound_email)
      end
    end

    describe ".inbound" do
      it "returns inbound messages" do
        expect(MessageLog.inbound).to contain_exactly(inbound_whatsapp)
      end
    end

    describe ".whatsapp" do
      it "returns whatsapp messages" do
        expect(MessageLog.whatsapp).to include(outbound_whatsapp, inbound_whatsapp)
        expect(MessageLog.whatsapp).not_to include(outbound_email)
      end
    end

    describe ".email" do
      it "returns email messages" do
        expect(MessageLog.email).to contain_exactly(outbound_email)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        logs = MessageLog.recent.to_a
        expect(logs.first.created_at).to be >= logs.last.created_at
      end
    end
  end
end
