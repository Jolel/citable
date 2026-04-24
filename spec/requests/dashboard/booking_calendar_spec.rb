# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::BookingCalendar", type: :request do
  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    allow(ReminderJob).to receive(:set).and_return(double(perform_later: true))
  end

  let(:account) { create(:account) }
  let(:owner) { create(:user, :owner, account: account) }
  let(:staff) { create(:user, account: account) }
  let(:other_staff) { create(:user, account: account) }
  let(:service) { create(:service, account: account, duration_minutes: 60) }
  let(:customer) { create(:customer, account: account, name: "Rosa Martínez") }
  let!(:booking) do
    create(
      :booking,
      account: account,
      user: staff,
      service: service,
      customer: customer,
      starts_at: Time.zone.parse("2026-04-20 10:00"),
      ends_at: Time.zone.parse("2026-04-20 11:00")
    )
  end
  let!(:other_staff_availability) do
    create(
      :staff_availability,
      account: account,
      user: other_staff,
      day_of_week: 1,
      start_time: "09:00",
      end_time: "18:00"
    )
  end

  before do
    sign_in owner
  end

  describe "GET /dashboard/calendar" do
    it "renders the week calendar view" do
      get dashboard_calendar_path(view: "week", date: "2026-04-20")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Semana")
      expect(response.body).to include("Rosa")
      expect(response.body).to include(staff.display_name)
      expect(response.body).to include("data-timed-column-date=\"2026-04-20\"")
      expect(response.body).not_to include("data-column-user-id")
    end

    it "renders the month calendar view" do
      get dashboard_calendar_path(view: "month", date: "2026-04-20")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mes")
      expect(response.body).to include("Abril 2026")
      expect(response.body).to include("Rosa")
      expect(response.body).to include("grid-template-columns: repeat(7, minmax(0, 1fr));")
    end
  end

  describe "PATCH /dashboard/calendar/events/:id" do
    it "updates the booking and returns JSON" do
      patch event_dashboard_calendar_path(booking),
        params: {
          booking: {
            starts_at: "2026-04-20T12:00:00-06:00",
            user_id: other_staff.id
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("booking", "user_id")).to eq(other_staff.id)
      expect(response.parsed_body["warning_message"]).to be_nil
    end

    it "includes a warning message when booking falls outside staff availability" do
      patch event_dashboard_calendar_path(booking),
        params: {
          booking: {
            starts_at: "2026-04-20T19:00:00-06:00",
            user_id: other_staff.id
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["warning_message"]).to be_present
    end
  end
end
