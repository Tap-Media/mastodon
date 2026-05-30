# frozen_string_literal: true

class RecordStoryViewService < BaseService
  def call(story, viewer_account)
    now = Time.now.utc

    if story.account_id == viewer_account.id
      StoryCache.mark_seen!(viewer_account_id: viewer_account.id, story_id: story.id, expires_at: story.expires_at)
      return StoryView.find_or_initialize_by(story: story, viewer_account: viewer_account).tap do |story_view|
        story_view.first_viewed_at ||= now
        story_view.last_viewed_at = now
      end
    end

    story_view = nil
    first_view = false

    Story.transaction do
      story_view = StoryView.lock.find_or_initialize_by(story: story, viewer_account: viewer_account)

      if story_view.new_record?
        story_view.first_viewed_at = now
        story_view.last_viewed_at  = now
        story_view.impression_count = 1
        story_view.save!
        first_view = true
      else
        story_view.update!(
          last_viewed_at: now,
          impression_count: story_view.impression_count + 1
        )
      end

      story.increment!(:viewer_count) if first_view
    end

    StoryCache.mark_seen!(viewer_account_id: viewer_account.id, story_id: story.id, expires_at: story.expires_at)

    story_view
  end
end
