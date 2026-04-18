class Webhooks::StripeController < ActionController::Base
  skip_forgery_protection

  WEBHOOK_SECRET = Rails.application.credentials.dig(:stripe, :webhook_secret)

  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, WEBHOOK_SECRET)
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      return head :bad_request
    end

    case event.type
    when "payment_intent.succeeded"
      handle_payment_succeeded(event.data.object)
    when "payment_intent.payment_failed"
      handle_payment_failed(event.data.object)
    end

    head :ok
  end

  private

  def handle_payment_succeeded(payment_intent)
    booking = Booking.find_by(stripe_payment_intent_id: payment_intent.id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      booking.update!(deposit_state: :deposit_paid)
      booking.confirm!
    end
  end

  def handle_payment_failed(payment_intent)
    booking = Booking.find_by(stripe_payment_intent_id: payment_intent.id)
    return unless booking

    ActsAsTenant.with_tenant(booking.account) do
      booking.update!(deposit_state: :deposit_pending)
    end
  end
end
