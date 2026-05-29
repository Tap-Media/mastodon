# frozen_string_literal: true

class CreateStoryViews < ActiveRecord::Migration[8.1]
  def change
    create_table :story_views do |t|
      t.references :story, null: false, foreign_key: true
      t.references :viewer_account, null: false, foreign_key: { to_table: :accounts }
      t.datetime :first_viewed_at, null: false
      t.datetime :last_viewed_at, null: false
      t.integer :impression_count, null: false, default: 1

      t.timestamps
    end

    add_index :story_views, [:story_id, :viewer_account_id], unique: true
    add_index :story_views, [:viewer_account_id, :last_viewed_at]
  end
end
