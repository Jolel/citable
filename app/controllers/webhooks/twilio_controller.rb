class Webhooks::TwilioController < ActionController::Base
  skip_forgery_protection

  def create
    from = params[:From]
    body = params[:Body]&.strip

    customer = Customer.joins(:account)
                       .find_by("phone LIKE ?", "%#{from.gsub(/\D/, "").last(10)}%")

    if customer
      ActsAsTenant.with_tenant(customer.account) do
        handle_reply(customer, body)
      end
    end

    head :ok
  end

  private

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
