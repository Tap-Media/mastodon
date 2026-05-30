# frozen_string_literal: true

# == Schema Information
#
# Table name: story_views
#
#  id                :bigint(8)        not null, primary key
#  first_viewed_at   :datetime         not null
#  impression_count  :integer          default(1), not null
#  last_viewed_at    :datetime         not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  story_id          :bigint(8)        not null
#  viewer_account_id :bigint(8)        not null
#
class StoryView < ApplicationRecord
  belongs_to :story, inverse_of: :story_views
  belongs_to :viewer_account, class_name: 'Account'

  validates :story_id, uniqueness: { scope: :viewer_account_id }
  validates :first_viewed_at, :last_viewed_at, presence: true
  validates :impression_count, numericality: { greater_than_or_equal_to: 1 }
end
