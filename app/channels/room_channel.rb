class RoomChannel < ApplicationCable::Channel  
  def subscribed
#    Dotenv.load unless ENV['SHARED_VERIFIER']
    @room_id = params[:room_id]
    @user_id = params[:user_id]
    code, ts = (params[:verifier] || '').split(/:/)
    return reject unless @room_id
    return reject unless ts.to_i > 6.hours.ago.to_i 
    # return reject unless code == GoSecure.sha512("#{@room_id}:#{@user_id}:#{ts}", "room_join_verifier", ENV['SHARED_VERIFIER'])
    stream_from RoomChannel.room_key(@room_id)
    RedisAccess.default.hset(self.users_key, @user_id, Time.now.to_i)
    RedisAccess.default.expire(self.users_key, 6.hours.to_i)
    self.broadcast_users
  end

  def unsubscribed
    @user_id = params[:user_id]
    RedisAccess.default.hdel(self.users_key, @user_id)
  end

  def receive(data)
    @room_id = params[:room_id]
    @user_id = params[:user_id]
    room_communicator = false
    RedisAccess.default.hset(self.users_key, @user_id, Time.now.to_i)
    RedisAccess.default.expire(self.users_key, 6.hours.to_i)
    communicator_id, partner_id = (RedisAccess.default.get("cdws/room_pair/#{@room_id}") || "").split(/:/, 2)
    if data['type'] == 'request'
      # Tell the communicator someone wants to 
      # connect with them. NOTE: This should key
      # off of device_id so that if someone logs
      # in on another device it won't mess it up
      RoomChanneel.broadcast({
        type: 'pair_request',
        communicator_id: data['communicator_id'],
        partner_id: @user_id
      })
    elsif data['type'] == 'accept'
      # Only allow one pairing at a time
      # Record the current pairing and only allow
      # assertions from that pair of user/devices
      if room_communicator
        RedisAccess.default.setex("cdws/room_pair/#{@room_id}", "#{@user_id}:#{data['partner_id']}", 30.minutes.to_i)
        RoomChannel.broadcast(@room_id, {
          type: 'pair_confirm',
          communicator_id: @user_id,
          partner_id: data['partner_id']
        })
      end
    elsif data['type'] == 'update'
      # The room author can always send updates,
      # and the currently-accepted partner can also
      # send updates.
      # Updates include:
      # - current board_id (obfuscated)
      # - current level
      # - showing all buttons
      # - current utterance text (encrypted)
      # - showing inflections
      # - activated button_id
      if room_communicator || @user_id == partner_id
        if @user_id == partner_id || @user_id == communicator_id
          if data['paired']
            RedisAccess.default.setex("cdws/room_pair/#{@room_id}", "#{communicator_id}:#{partner_id}", 30.minutes.to_i)
          end
          data['user_id'] = @user_id
          RoomChannel.broadcast(@room_id, data)
        end
      end
    elsif data['type'] == 'confirm'
      if @user_id == communicator_id || @user_id == partner_id
        data['user_id'] = @user_id
        RoomChannel.broadcast(@room_id, data)
      end
      # When paired, updates should be confirmed
      # or re-sent
    elsif data['type'] == 'users'
      self.broadcast_users      
    elsif ['ping', 'pong', 'candidate', 'offer', 'answer'].include?(data['type'])
      if @user_id == communicator_id || @user_id == partner_id
        # WebRTC messages
        RoomChannel.broadcast(@room_id, data)
      end
    elsif data['type'] == 'keepalive'
      # Nothing to broadcast
    else
      RoomChannel.broadcast(@room_id , {type: 'noop'})
    end
  end

  def broadcast_users
    users = RedisAccess.default.hgetall(self.users_key) || {}
    user_ids = []
    users.each do |user_id, ts|
      if ts.to_i < 30.minutes.ago.to_i
        RedisAccess.default.hdel(self.users_key, @user_id)
      else
        user_ids << user_id
      end
    end
    RoomChannel.broadcast(@room_id, {
      type: 'users',
      list: user_ids
    })
  end

  def self.room_key(room_id)
    "cdws/room_#{room_id}"
  end

  def users_key
    "cdws/users_for_#{@room_id}"
  end

  def self.broadcast(room_id, message)
    ActionCable.server.broadcast(RoomChannel.room_key(room_id), message)
  end
end  