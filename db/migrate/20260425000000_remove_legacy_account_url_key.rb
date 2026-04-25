class RemoveLegacyAccountUrlKey < ActiveRecord::Migration[8.1]
  LEGACY_COLUMN = %w[sub domain].join.freeze

  def up
    remove_column :accounts, LEGACY_COLUMN, :string if column_exists?(:accounts, LEGACY_COLUMN)
  end

  def down
    return if column_exists?(:accounts, LEGACY_COLUMN)

    add_column :accounts, LEGACY_COLUMN, :string
    add_index :accounts, LEGACY_COLUMN, unique: true
  end
end
