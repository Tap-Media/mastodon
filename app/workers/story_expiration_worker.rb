# frozen_string_literal: true

class StoryExpirationWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, lock: :until_executed, lock_ttl: 5.minutes.to_i

  def perform(story_id)
    story = Story.find_by(id: story_id)
    return if story.nil? || story.deleted?

    story.expire!
    StoryCleanupWorker.perform_async(story.id) if story.expired?
  end
end
