class RoomChannel < ApplicationCable::Channel  
  def subscribed
#    Dotenv.load unless ENV['SHARED_VERIFIER']
    @room_id = params[:room_id]
    @user_id = params[:user_id]
    code, ts = (params[:verifier] || '').split(/:/)
    return reject unless @room_id
    return reject unless ts.to_i > 6.hours.ago.to_i 
    return reject unless code == GoSecure.sha512("#{@room_id}:#{@user_id}:#{ts}", "room_join_verifier", ENV['SHARED_VERIFIER'])[0, 30]
    stream_from RoomChannel.room_key(@room_id)
    RedisAccess.default.hset(self.users_key, @user_id, Time.now.to_i)
    RedisAccess.default.expire(self.users_key, 6.hours.to_i)
    self.room_users(true)
  end

  def unsubscribed
    @user_id = params[:user_id]
    RedisAccess.default.hdel(self.users_key, @user_id)
  end

  def receive(data)
    @room_id = params[:room_id]
    @user_id = params[:user_id]
    room_communicator = @user_id && @user_id.match(/^me/)
    RedisAccess.default.hset(self.users_key, @user_id, Time.now.to_i)
    RedisAccess.default.expire(self.users_key, 6.hours.to_i)
    communicator_id, partner_id, pair_code = (RedisAccess.default.get("cdws/room_pair/#{@room_id}") || "").split(/:/, 3)
    if data['type'] == 'request'
      # Tell the communicator someone wants to 
      # connect with them. NOTE: This should key
      # off of device_id so that if someone logs
      # in on another device it won't mess it up
      # Users can optionally enable auto-accept
      user_ids = self.room_users(false)
      msg = {
        type: 'pair_request',
        communicator_ids: user_ids.select{|id| id.match(/^me/) },
        preferred_communicator_id: data['communicator_id'],
        pair_code: data['pair_code'],
        partner_id: @user_id,
      }
      if room_communicator && data['driving']
        RedisAccess.default.setex("cdws/room_pair/#{@room_id}", 30.minutes.to_i, "driving:#{@user_id}:#{data['pair_code']}")
        RoomChannel.broadcast(@room_id, {
          type: 'pair_confirm',
          communicator_id: 'driving',
          pair_code: data['pair_code'],
          partner_id: @user_id
        })
      else
        RoomChannel.broadcast(@room_id, msg)
      end
    elsif data['type'] == 'query'
      # Ask the communicator to send an update
      # NOTE: Multiple followers are allowed
      # NOTE: This will potentially get updates from
      # multiple devices at the same time, not sure
      # how to handle that
      RoomChannel.broadcast(@room_id, data)
    elsif data['type'] == 'accept'
      # Only allow one pairing at a time
      # Record the current pairing and only allow
      # assertions from that pair of user/devices
      if room_communicator && data['pair_code'] != pair_code
        RedisAccess.default.setex("cdws/room_pair/#{@room_id}", 30.minutes.to_i, "#{@user_id}:#{data['partner_id']}:#{data['pair_code']}")
        RoomChannel.broadcast(@room_id, {
          type: 'pair_confirm',
          communicator_id: @user_id,
          pair_code: data['pair_code'],
          partner_id: data['partner_id']
        })
      end
    elsif data['type'] == 'reject'
      # If all connected communicators reject,
      # tell them it's not going to happen
      if room_communicator && data['pair_code'] != pair_code
        user_ids = self.room_users(false)
        communicator_ids = user_ids.select{|id| id.match(/^me/) }.uniq
        reject_key = "cdws/room_pair/rejected/#{@room_id}/#{data['pair_code']}"
        RedisAccess.default.hset(reject_key, @user_id, 'true')
        RedisAccess.default.expire(reject_key, 30.minutes.to_i)
        rejected_user_ids = (RedisAccess.default.hgetall(self.users_key) || {}).keys
        if (communicator_ids - rejected_user_ids).empty?
          RoomChannel.broadcast(@room_id, {
            type: 'pair_reject',
            communicator_id: @user_id,
            pair_code: data['pair_code'],
            partner_id: data['partner_id']
          })
        end
      end
    elsif data['type'] == 'message'
      # Broadcast the message, and then the communicator's
      # device can decide if it's a valid user or not
      RoomChannel.broadcast(@room_id, {
        type: 'message',
        sender_id: @user_id,
        message: data['message'],
        message_id: data['message_id']
      })
    elsif data['type'] == 'unpair'
      if @user_id == partner_id || @user_id == communicator_id
        RedisAccess.default.del("cdws/room_pair/#{@room_id}")
        RoomChannel.broadcast(@room_id, {
          type: 'pair_end',
          communicator_id: communicator_id,
          partner_id: partner_id
        })
      else
        RoomChannel.broadcast(@room_id, {
          type: 'unfollow',
          communicator_id: communicator_id,
          partner_id: partner_id
        })
      end
    elsif data['type'] == 'update'
      # The room author can always send updates,
      # and the currently-accepted partner can also
      # send updates.
      # Updates include:
      # - last user action (for negotiating when following and multiple updates happen)
      # - installed_app (for negotiating when following and multiple updates happen)
      # - current board_id (obfuscated)
      # - current focus words
      # - current level
      # - showing all buttons
      # - current utterance text (encrypted)
      # - showing inflections
      # - activated button_id
      if room_communicator || @user_id == partner_id
        if @user_id == partner_id || @user_id == communicator_id || (room_communicator && communicator_id == 'driving')
          if data['paired']
            RedisAccess.default.setex("cdws/room_pair/#{@room_id}", 30.minutes.to_i, "#{communicator_id}:#{partner_id}:#{pair_code}")
          end
          if data['unpaired']
            RedisAccess.default.del("cdws/room_pair/#{@room_id}")
          else
            data['paired_communicator_id'] = communicator_id
            data['paired_partner_id'] = partner_id
            data['pair_code'] = pair_code
          end
        end
        data['user_id'] = @user_id
        RoomChannel.broadcast(@room_id, data)
      else
        raise "no update auth"
      end
    elsif data['type'] == 'confirm'
      if @user_id == communicator_id || @user_id == partner_id || (room_communicator && communicator_id == 'driving')
        data['user_id'] = @user_id
        RoomChannel.broadcast(@room_id, data)
      end
      # When paired, updates should be confirmed
      # or re-sent
    elsif data['type'] == 'users'
      self.room_users(true)      
    elsif ['ping', 'pong', 'candidate', 'offer', 'answer'].include?(data['type'])
      if @user_id == communicator_id || @user_id == partner_id
        # WebRTC messages
        RoomChannel.broadcast(@room_id, data)
      end
    elsif data['type'] == 'keepalive'
      if data['following']
        RoomChannel.broadcast(@room_id, {
          type: 'following',
          sender_id: @user_id
        })
      end
      # Nothing to broadcast
    else
      RoomChannel.broadcast(@room_id , {type: 'noop'})
    end
  end

  def room_users(broadcast=true)
    users = RedisAccess.default.hgetall(self.users_key) || {}
    user_ids = []
    last_access_ts = nil
    users.each do |user_id, ts|
      if ts.to_i < 30.minutes.ago.to_i
        RedisAccess.default.hdel(self.users_key, @user_id)
      else
        user_ids << user_id
        if user_id.match(/^me/)
          last_access_ts = [last_access_ts || ts, ts].max
        end
      end
    end
    RoomChannel.broadcast(@room_id, {
      type: 'users',
      last_communicator_access: last_access_ts,
      list: user_ids
    }) if broadcast
    return user_ids
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