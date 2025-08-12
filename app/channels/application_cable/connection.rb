module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :uuid

    def connect
      self.uuid = SecureRandom.uuid
    end

    private

    def find_verified_user
      # Add any user authentication logic here if needed
      # For now, we'll just allow all connections
    end
  end
end
