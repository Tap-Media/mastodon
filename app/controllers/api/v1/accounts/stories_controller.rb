# frozen_string_literal: true

class Api::V1::Accounts::StoriesController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read }, only: :index
  before_action :require_user!
  before_action :set_account

  def index
    @stories = Story.active
      .where(account: @account)
      .includes(:account, :story_views, story_media: :media_attachment)
      .oldest_first
      .select { |story| story.visible_to?(current_account) }

    render json: @stories, each_serializer: REST::StorySerializer
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end
end
