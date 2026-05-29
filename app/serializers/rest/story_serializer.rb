# frozen_string_literal: true

class REST::StorySerializer < ActiveModel::Serializer
  attributes :id, :caption, :privacy, :status, :published_at, :expires_at, :viewer_count, :seen

  belongs_to :account, serializer: REST::AccountSerializer
  has_many :ordered_media_attachments, key: :media_attachments, serializer: REST::MediaAttachmentSerializer

  def id
    object.id.to_s
  end

  def viewer_count
    object.viewer_count.to_i
  end

  def seen
    current_user.present? && object.seen_by?(current_user.account)
  end
end
