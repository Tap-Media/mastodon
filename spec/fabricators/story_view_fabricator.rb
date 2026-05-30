# frozen_string_literal: true

Fabricator(:story_view) do
  story
  viewer_account { Fabricate(:account) }
  first_viewed_at { Time.now.utc }
  last_viewed_at { Time.now.utc }
  impression_count 1
end
