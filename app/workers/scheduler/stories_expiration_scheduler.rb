# frozen_string_literal: true

class Scheduler::StoriesExpirationScheduler
  include Sidekiq::Worker

  sidekiq_options retry: 0, lock: :until_executed, lock_ttl: 10.minutes.to_i

  def perform
    due_stories.find_each do |story|
      StoryExpirationWorker.perform_async(story.id)
    end
  end

  private

  def due_stories
    Story.expired_or_due.select(:id)
  end
end
