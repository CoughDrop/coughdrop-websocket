class ApplicationController < ActionController::Base
  skip_before_action :verify_authenticity_token
  before_action :set_app_headers

  def set_app_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, PUT, OPTIONS'
    headers['Feature-Policy'] = 'camera *; autoplay *; display-capture *; fullscreen *';
  end
end
