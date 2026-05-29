# frozen_string_literal: true

class CreateStories < ActiveRecord::Migration[8.1]
  def change
    create_table :stories do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.text :caption
      t.string :privacy, null: false, default: 'public'
      t.string :status, null: false, default: 'published'
      t.datetime :published_at, null: false
      t.datetime :expires_at, null: false
      t.bigint :viewer_count, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :stories, [:account_id, :published_at], order: { published_at: :desc }
    add_index :stories, [:status, :expires_at]
    add_index :stories, :expires_at
  end
end
