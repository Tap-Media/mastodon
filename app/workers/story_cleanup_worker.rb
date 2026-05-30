# frozen_string_literal: true

class StoryCleanupWorker
  include Sidekiq::Worker
  include Redisable

  sidekiq_options retry: 3, lock: :until_executed, lock_ttl: 5.minutes.to_i

  def perform(story_id)
    story = Story.find_by(id: story_id)
    return if story.nil?

    StoryCache.clear_story!(story.id)
    story.touch(:updated_at)
  end
end
