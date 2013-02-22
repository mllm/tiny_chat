require 'goliath'
require 'redis'

module Options
  def self.redis
    options = {driver: :synchrony}
    if ENV['REDIS_URI']
      uri = URI.parse(ENV['REDIS_URI'])
      options.merge!({host: uri.host, port: uri.port, password: uri.password})
    end
    options
  end
end

class Subscribe < Goliath::API
  def response(env)
    EM.synchrony do
      @redis = Redis.new(Options::redis)
      channel = env["REQUEST_PATH"].sub(/^\/subscribe\//, '')
      @redis.subscribe(channel) do |on|
        on.message do |channel, hook|
          env.stream_send("#{hook}\r\n\n")
        end
      end
    end
    EventMachine.add_periodic_timer(30) do
      env.stream_send("\r\n\n")
    end
    streaming_response(200, { 'Content-Type' => "text/event-stream" })
  end

  def on_close(env)
    @redis.disconnect
  end
end

class Receive < Goliath::API
  @@redis = Redis.new(Options::redis)

  def response(env)
    channel = env["REQUEST_PATH"][1..-1]
    require 'pry'
    binding.pry
    #sender
    @@redis.publish(channel, "#{sender}:#{message}")
    [ 200, { }, [ ] ]
  end
end

class Server < Goliath::API
  map "/" do
    run Rack::File.new(File.join(File.dirname(__FILE__), 'public', 'index.html'))
  end

  map /^\/subscribe.*/ do
    run Subscribe.new
  end

  map /.*/ do
    run Receive.new
  end
end