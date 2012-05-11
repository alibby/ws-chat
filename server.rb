require 'rubygems'
require 'em-websocket'
require 'sinatra/base'
require 'thin'
require 'haml'
require 'json'

# Store sessions in memory - keyed by the object_id of
# the underlying websocket connection.  Since we always
# get the same ws connection back with the same object_id
# this seemed like a good safe hash key to use.
class SessionStore
  def initialize
    @sessions = Hash.new
  end

  def <<(session)
    session.session_store = self
    @sessions[ session.connection.object_id ] = session
  end

  def delete_for_connection(ws)
    @sessions.delete(ws.object_id)
  end

  def with_connection(ws,&blk)
    yield @sessions[ ws.object_id ]
  end

  def each_peer(session, &blk)
    @sessions.values.reject { |s| s == session }.each { |s| yield s }
  end

  def each(&blk)
    @sessions.values.each { |s| yield s }
  end
end

class ChatSession
  attr_accessor :username, :connection, :session_store
  def initialize(ws)
    @session_store = nil
    @connection = ws
    @username = ''
  end

  def send(message)
    puts "--> (%s) %s" % [ username, message.to_json ]
    @connection.send( message.to_json )
  end

  def receive(message)
    puts "<-- (%s) %s" % [ username, message.to_json ]
    case message.type
      when 'connect' then
        self.username = message.content
        session_store.each_peer(self) { |peer| peer.send message }
      when 'chat' then
        session_store.each { |s| s.send(message) }
    end
  end
end

class ChatMessage
  attr_accessor :type, :content

  def initialize(type, content)
    @type = type
    @content = content
  end

  def self.parse(packet)
    tmp = JSON.parse(packet)
    new tmp['type'], tmp['content']
  end

  def to_json
    {
      type: self.type,
      content: self.content,
      timestamp: DateTime.now.to_s
    }.to_json
  end
end

EventMachine.run do
  class App < Sinatra::Base
    get '/' do
      haml :index
    end
  end

  @sessions = SessionStore.new

  EventMachine::WebSocket.start(:host => '0.0.0.0', :port => 3001) do |ws|

    ws.onopen {
      @sessions << ChatSession.new(ws)
    }

    ws.onmessage { |packet|
      @sessions.with_connection(ws) do |session|
        session.receive( ChatMessage.parse(packet) )
      end
    }

    ws.onclose {
      left = @sessions.delete_for_connection(ws)
      @sessions.each { |s| s.send(ChatMessage.new("disconnect", left.username)) }
    }
  end

  App.run!({:port => 3000})
end

