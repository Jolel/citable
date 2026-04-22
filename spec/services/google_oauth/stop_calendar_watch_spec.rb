# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::StopCalendarWatch do
  let(:user)     { create(:user, :google_connected) }
  let(:calendar) { instance_double(GoogleOauth::CalendarAdapter) }

  describe ".call" do
    context "when user has no google_channel_id" do
      before { user.update_columns(google_channel_id: nil) }

      it "returns Success without calling the adapter" do
        expect(calendar).not_to receive(:stop_channel)
        result = described_class.call(user: user, calendar: calendar)
        expect(result).to be_success
      end
    end

    context "when user has a google_channel_id" do
      before { user.update_columns(google_channel_id: "channel-123") }

      it "calls stop_channel on the adapter and returns Success" do
        expect(calendar).to receive(:stop_channel).with("channel-123")
        result = described_class.call(user: user, calendar: calendar)
        expect(result).to be_success
      end

      context "when stop_channel raises an error" do
        before { allow(calendar).to receive(:stop_channel).and_raise(RuntimeError, "network error") }

        it "swallows the error and returns Success" do
          result = described_class.call(user: user, calendar: calendar)
          expect(result).to be_success
        end
      end
    end
  end
end
