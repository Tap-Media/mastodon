# frozen_string_literal: true

class StoryTrayService < BaseService
  def initialize(account)
    super()

    @account = account
  end

  def call
    grouped_visible_stories.values
      .filter_map { |stories| stories.max_by(&:published_at) }
      .sort_by { |story| [-story.published_at.to_i, -story.id] }
  end

  private

  attr_reader :account

  def grouped_visible_stories
    visible_stories.group_by(&:account_id)
  end

  def visible_stories
    Story.active
      .includes(:account, :story_views, story_media: :media_attachment)
      .recent_first
      .select { |story| story.visible_to?(account) }
  end
end
