# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::DisconnectCalendar do
  let(:user)     { create(:user, :google_connected) }
  let(:calendar) { instance_double(GoogleOauth::CalendarAdapter) }

  describe ".call" do
    context "when user has no channel (StopCalendarWatch is a no-op)" do
      before { user.update_columns(google_channel_id: nil) }

      it "clears google credentials and returns Success" do
        result = described_class.call(user: user, calendar: calendar)
        expect(result).to be_success
        expect(result.value!).to be_a(User)
        expect(user.reload.google_oauth_token).to be_nil
        expect(user.reload.google_refresh_token).to be_nil
      end
    end

    context "when user has an active channel" do
      before { user.update_columns(google_channel_id: "ch-999") }

      it "stops the channel before disconnecting" do
        expect(calendar).to receive(:stop_channel).with("ch-999")
        described_class.call(user: user, calendar: calendar)
      end

      it "clears all google fields and returns Success" do
        allow(calendar).to receive(:stop_channel)
        result = described_class.call(user: user, calendar: calendar)
        expect(result).to be_success
        user.reload
        expect(user.google_oauth_token).to be_nil
        expect(user.google_calendar_id).to be_nil
        expect(user.google_channel_id).to be_nil
      end
    end

    context "when disconnect_google! raises ActiveRecord::RecordInvalid" do
      before do
        user.update_columns(google_channel_id: nil)
        allow(user).to receive(:disconnect_google!).and_raise(ActiveRecord::RecordInvalid.new(user))
      end

      it "returns Failure(:disconnect_failed)" do
        result = described_class.call(user: user, calendar: calendar)
        expect(result).to be_failure.and(have_attributes(failure: :disconnect_failed))
      end
    end
  end
end
