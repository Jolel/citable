# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::NluMetrics", type: :request do
  let(:account) { create(:account, ai_nlu_enabled: true) }
  let(:owner)   { create(:user, :owner, account: account) }

  before { sign_in owner }

  describe "GET /dashboard/nlu_metrics" do
    context "when not authenticated" do
      before { sign_out owner }

      it "redirects to sign-in" do
        get dashboard_nlu_metrics_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "with no AI logs" do
      it "returns 200 and shows zero totals" do
        get dashboard_nlu_metrics_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("0")
      end
    end

    context "with NLU message logs" do
      let(:customer) { create(:customer, account: account) }

      before do
        create(:message_log, account: account, customer: customer,
               direction: "inbound", channel: "whatsapp",
               ai_model: "gemini-2.5-pro", ai_intent: "services_list",
               ai_confidence: 0.92, ai_latency_ms: 1200, ai_prompt_version: "v1")
        create(:message_log, account: account, customer: customer,
               direction: "inbound", channel: "whatsapp",
               ai_model: "gemini-2.5-pro", ai_intent: "booking",
               ai_confidence: 0.55, ai_latency_ms: 900, ai_prompt_version: "v1")
      end

      it "shows intent distribution" do
        get dashboard_nlu_metrics_path
        expect(response.body).to include("services_list")
        expect(response.body).to include("booking")
      end

      it "shows prompt version" do
        get dashboard_nlu_metrics_path
        expect(response.body).to include("v1")
      end

      it "shows total call count" do
        get dashboard_nlu_metrics_path
        expect(response.body).to include("2")
      end
    end

    context "tenant isolation" do
      let(:other_account)  { create(:account) }
      let(:other_customer) { create(:customer, account: other_account) }

      before do
        create(:message_log, account: other_account, customer: other_customer,
               direction: "inbound", channel: "whatsapp",
               ai_model: "gemini-2.5-pro", ai_intent: "other_intent",
               ai_latency_ms: 500)
      end

      it "does not include other accounts' logs" do
        get dashboard_nlu_metrics_path
        expect(response.body).not_to include("other_intent")
      end
    end
  end
end
