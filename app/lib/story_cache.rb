# frozen_string_literal: true

class StoryCache
  class << self
    def mark_seen!(viewer_account_id:, story_id:, expires_at:)
      ttl = [(expires_at.to_i - Time.now.utc.to_i), 1].max

      RedisConnection.with do |redis|
        redis.set(seen_key(viewer_account_id, story_id), 1, ex: ttl)
      end
    end

    def seen?(viewer_account_id:, story_id:)
      RedisConnection.with do |redis|
        redis_key_exists?(redis, seen_key(viewer_account_id, story_id))
      end
    end

    def clear_story!(story_id)
      RedisConnection.with do |redis|
        delete_by_pattern(redis, "stories:seen:*:#{story_id}")
      end
    end

    def seen_key(viewer_account_id, story_id)
      "stories:seen:#{viewer_account_id}:#{story_id}"
    end

    private

    def delete_by_pattern(redis, pattern)
      keys = redis.scan_each(match: pattern, count: 1_000).to_a
      redis.del(keys) if keys.any?
    end

    def redis_key_exists?(redis, key)
      exists = redis.exists?(key)
      case exists
      when true
        true
      when false, nil
        false
      else
        exists.to_i.positive?
      end
    end
  end
end
