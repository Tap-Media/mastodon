# frozen_string_literal: true

# == Schema Information
#
# Table name: story_media
#
#  id                  :bigint(8)        not null, primary key
#  position            :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  media_attachment_id :bigint(8)        not null
#  story_id            :bigint(8)        not null
#
class StoryMedium < ApplicationRecord
  self.table_name = 'story_media'

  belongs_to :story, inverse_of: :story_media
  belongs_to :media_attachment, inverse_of: :story_medium

  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :story_id, uniqueness: { scope: :position }
  validates :media_attachment_id, uniqueness: true
end
