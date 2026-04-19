class Webhooks::TwilioController < ActionController::Base
  skip_forgery_protection

  before_action :verify_twilio_signature

  def create
    from = params[:From]
    body = params[:Body]&.strip

    normalized = from.gsub(/\D/, "")
    customer = Customer.joins(:account)
                       .find_by("regexp_replace(phone, '[^0-9]', '', 'g') = ?", normalized)

    if customer
      ActsAsTenant.with_tenant(customer.account) do
        handle_reply(customer, body)
      end
    end

    head :ok
  end

  private

  def verify_twilio_signature
    auth_token = Rails.application.credentials.dig(:twilio, :auth_token)
    validator  = Twilio::Security::RequestValidator.new(auth_token)
    unless validator.validate(request.url, params.to_unsafe_h, request.headers["X-Twilio-Signature"])
      head :forbidden
    end
  end

  def handle_reply(customer, body)
    pending_booking = customer.bookings.active.upcoming.first
    return unless pending_booking

    MessageLog.create!(
      account: customer.account,
      customer: customer,
      booking: pending_booking,
      channel: "whatsapp",
      direction: "inbound",
      body: body,
      status: "delivered"
    )

    case body
    when "1"
      pending_booking.confirm!
    when "2"
      pending_booking.cancel!
    end
  end
end
