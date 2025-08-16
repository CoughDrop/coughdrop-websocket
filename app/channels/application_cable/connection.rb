module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :uuid

    def connect
      # Basic connection validation
      return reject unless request.params[:room_id]
      return reject unless request.params[:user_id]
      return reject unless request.params[:verifier]
      
      self.uuid = SecureRandom.uuid
    end

    private

    def find_verified_user
      # Add any user authentication logic here if needed
      # For now, we'll just allow all connections
    end
  end
end
