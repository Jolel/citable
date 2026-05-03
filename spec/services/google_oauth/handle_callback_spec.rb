# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauth::HandleCallback do
  let(:account)       { create(:account) }
  let(:owner)         { create(:user, :owner, account: account) }
  let(:staff)         { create(:user, account: account) }
  let(:redirect_uri)  { "https://app.example.com/oauth/callback" }
  let(:code)          { "auth_code_abc" }
  let(:nonce)         { "n0nc3-abc" }
  let(:session_nonce) { nonce }

  def valid_state(user_id:, initiator:, return_to: "/dashboard", state_nonce: nonce)
    GoogleOauth::BuildStateToken.call(
      user_id:      user_id,
      return_to:    return_to,
      initiator_id: initiator.id,
      nonce:        state_nonce
    ).value!
  end

  let(:connect_success) { Dry::Monads::Success({ user: staff, return_to: "/dashboard" }) }

  before do
    allow(GoogleOauth::ConnectCalendar).to receive(:call).and_return(connect_success)
  end

  describe ".call" do
    context "with a valid state and owner as current_user" do
      it "returns Success with user and return_to" do
        result = described_class.call(
          state:         valid_state(user_id: staff.id, initiator: owner),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: session_nonce
        )
        expect(result).to be_success
        expect(result.value![:user]).to eq(staff)
        expect(result.value![:return_to]).to eq("/dashboard")
      end
    end

    context "with a valid state where staff connects their own calendar" do
      it "returns Success" do
        result = described_class.call(
          state:         valid_state(user_id: staff.id, initiator: staff),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  staff,
          session_nonce: session_nonce
        )
        expect(result).to be_success
      end
    end

    context "when the state token is invalid" do
      it "returns Failure(:invalid_state)" do
        result = described_class.call(
          state:         "bad.token",
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: session_nonce
        )
        expect(result).to be_failure.and(have_attributes(failure: :invalid_state))
      end
    end

    context "when the initiator_id in the state does not match current_user" do
      it "returns Failure(:state_initiator_mismatch)" do
        result = described_class.call(
          state:         valid_state(user_id: staff.id, initiator: staff),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: session_nonce
        )
        expect(result).to be_failure.and(have_attributes(failure: :state_initiator_mismatch))
      end
    end

    context "when the session nonce does not match the state nonce" do
      it "returns Failure(:state_nonce_mismatch)" do
        result = described_class.call(
          state:         valid_state(user_id: staff.id, initiator: owner, state_nonce: "from_state"),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: "different"
        )
        expect(result).to be_failure.and(have_attributes(failure: :state_nonce_mismatch))
      end
    end

    context "when the user_id in the state does not belong to the account" do
      it "returns Failure(:user_not_found)" do
        result = described_class.call(
          state:         valid_state(user_id: 999_999, initiator: owner),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: session_nonce
        )
        expect(result).to be_failure.and(have_attributes(failure: :user_not_found))
      end
    end

    context "when a staff member tries to connect another user's calendar" do
      let(:other_staff) { create(:user, account: account) }

      it "returns Failure(:access_denied)" do
        result = described_class.call(
          state:         valid_state(user_id: other_staff.id, initiator: staff),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  staff,
          session_nonce: session_nonce
        )
        expect(result).to be_failure.and(have_attributes(failure: :access_denied))
      end
    end

    context "when ConnectCalendar fails" do
      before do
        allow(GoogleOauth::ConnectCalendar).to receive(:call)
          .and_return(Dry::Monads::Failure(:authorization_failed))
      end

      it "propagates the failure" do
        result = described_class.call(
          state:         valid_state(user_id: staff.id, initiator: owner),
          code:          code,
          redirect_uri:  redirect_uri,
          account:       account,
          current_user:  owner,
          session_nonce: session_nonce
        )
        expect(result).to be_failure.and(have_attributes(failure: :authorization_failed))
      end
    end
  end
end
