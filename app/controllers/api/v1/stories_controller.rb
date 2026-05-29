# frozen_string_literal: true

class Api::V1::StoriesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }, only: [:show, :tray]
  before_action -> { doorkeeper_authorize! :write }, only: [:create, :destroy, :view]
  before_action :require_user!
  before_action :set_story, only: [:show, :view]
  before_action :set_owned_story, only: :destroy

  def show
    render json: @story, serializer: REST::StorySerializer
  end

  def create
    media_attachments = selected_media_attachments
    return render json: { error: 'At least one media attachment is required' }, status: 422 if media_attachments.empty?

    @story = Story.build_with_media!(
      account: current_account,
      media_attachments: media_attachments,
      privacy: story_create_params.fetch(:privacy),
      caption: story_create_params[:caption]
    )

    StoryExpirationWorker.perform_at(@story.expires_at, @story.id)

    render json: @story, serializer: REST::StorySerializer
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: 422
  end

  def tray
    @stories = StoryTrayService.new(current_account).call
    render json: @stories, each_serializer: REST::StorySerializer
  end

  def view
    story_view = RecordStoryViewService.new.call(@story, current_account)

    render json: {
      story_id: @story.id.to_s,
      viewer_count: @story.reload.viewer_count,
      viewed_at: story_view.last_viewed_at,
    }
  end

  def destroy
    @story.mark_deleted!
    StoryCleanupWorker.perform_async(@story.id)
    render_empty
  end

  private

  def set_story
    @story = Story.active.includes(:account, :story_views, story_media: :media_attachment).find(params[:id])
    raise ActiveRecord::RecordNotFound unless @story.visible_to?(current_account)
  end

  def set_owned_story
    @story = current_account.stories.find(params[:id])
  end

  def story_create_params
    permitted = params.permit(:caption, :privacy, media_ids: [])
    permitted[:privacy] = permitted[:privacy].presence || 'public'

    raise(ActiveRecord::RecordInvalid, Story.new.tap { |story| story.errors.add(:privacy, 'is invalid') }) unless Story::PRIVACY_VALUES.include?(permitted[:privacy])

    permitted
  end

  def selected_media_attachments
    media_ids = Array(story_create_params[:media_ids]).map(&:to_i).uniq
    relation = current_account.media_attachments.where(id: media_ids, status_id: nil, scheduled_status_id: nil)

    media_attachments = relation.to_a

    raise(ActiveRecord::RecordInvalid, Story.new.tap { |story| story.errors.add(:media_ids, 'contains invalid records') }) unless media_attachments.size == media_ids.size
    raise(ActiveRecord::RecordInvalid, Story.new.tap { |story| story.errors.add(:media_ids, 'contains media still processing') }) if media_attachments.any?(&:not_processed?)
    raise(ActiveRecord::RecordInvalid, Story.new.tap { |story| story.errors.add(:media_ids, 'contains media already attached to a story') }) if StoryMedium.exists?(media_attachment_id: media_ids)

    media_attachments
  end
end
