# frozen_string_literal: true

Fabricator(:story) do
  account
  caption 'Story caption'
  privacy 'public'
  status 'published'
  published_at { Time.now.utc }
  expires_at { 24.hours.from_now }
  viewer_count 0
end
