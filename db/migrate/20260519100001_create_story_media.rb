# frozen_string_literal: true

class CreateStoryMedia < ActiveRecord::Migration[8.1]
  def change
    create_table :story_media do |t|
      t.references :story, null: false, foreign_key: true
      t.references :media_attachment, null: false, foreign_key: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :story_media, [:story_id, :position], unique: true
    add_index :story_media, :media_attachment_id, unique: true
  end
end
