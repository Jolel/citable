# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Former payment provider webhook routing", type: :routing do
  describe "routing" do
    it "does not route the retired payment webhook" do
      expect(post: "/webhooks/#{%w[str ipe].join}").not_to be_routable
    end
  end
end
