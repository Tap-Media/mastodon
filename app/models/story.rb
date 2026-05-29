# frozen_string_literal: true

# == Schema Information
#
# Table name: stories
#
#  id           :bigint(8)        not null, primary key
#  caption      :text
#  deleted_at   :datetime
#  expires_at   :datetime         not null
#  privacy      :string           default("public"), not null
#  published_at :datetime         not null
#  status       :string           default("published"), not null
#  viewer_count :bigint(8)        default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint(8)        not null
#
class Story < ApplicationRecord
  PRIVACY_VALUES = %w(public followers).freeze
  STATUS_VALUES  = %w(published expired deleted).freeze

  belongs_to :account

  has_many :story_media, -> { order(position: :asc) }, class_name: 'StoryMedium', dependent: :destroy, inverse_of: :story
  has_many :ordered_media_attachments, through: :story_media, source: :media_attachment
  has_many :story_views, dependent: :destroy, inverse_of: :story

  validates :privacy, inclusion: { in: PRIVACY_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :published_at, :expires_at, presence: true
  validates :viewer_count, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: 'published', deleted_at: nil).where(arel_table[:expires_at].gt(Time.now.utc)) }
  scope :expired_or_due, -> { where(status: 'published', deleted_at: nil).where(arel_table[:expires_at].lteq(Time.now.utc)) }
  scope :recent_first, -> { order(published_at: :desc, id: :desc) }
  scope :oldest_first, -> { order(published_at: :asc, id: :asc) }

  def active?
    status == 'published' && deleted_at.nil? && expires_at.future?
  end

  def deleted?
    status == 'deleted'
  end

  def expired?
    status == 'expired'
  end

  def public_privacy?
    privacy == 'public'
  end

  def followers_privacy?
    privacy == 'followers'
  end

  def seen_by?(viewer_account)
    return false if viewer_account.nil?

    if story_views.loaded?
      story_views.any? { |story_view| story_view.viewer_account_id == viewer_account.id }
    else
      StoryCache.seen?(viewer_account_id: viewer_account.id, story_id: id) || story_views.exists?(viewer_account_id: viewer_account.id)
    end
  end

  def visible_to?(viewer_account)
    return false if deleted? || expired? || expires_at.past? || account.unavailable?
    return true if viewer_account == account
    return false if viewer_account.nil?
    return false if account.blocking?(viewer_account) || viewer_account.blocking?(account)

    public_privacy? || viewer_account.following?(account)
  end

  def expire!
    return if deleted? || expired? || expires_at.future?

    update!(status: 'expired')
  end

  def mark_deleted!
    update!(status: 'deleted', deleted_at: Time.now.utc)
  end

  def self.build_with_media!(account:, media_attachments:, privacy:, caption: nil)
    now = Time.now.utc

    transaction do
      story = create!(
        account: account,
        caption: caption,
        privacy: privacy,
        status: 'published',
        published_at: now,
        expires_at: now + 24.hours
      )

      media_attachments.each_with_index do |media_attachment, index|
        story.story_media.create!(media_attachment: media_attachment, position: index)
      end

      story
    end
  end
end
