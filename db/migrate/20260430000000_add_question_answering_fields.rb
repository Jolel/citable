# frozen_string_literal: true

class AddQuestionAnsweringFields < ActiveRecord::Migration[8.1]
  def change
    add_column :services, :description, :text
    add_column :accounts, :business_hours, :jsonb, default: {}, null: false
  end
end
