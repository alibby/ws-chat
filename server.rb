require 'rubygems'
require 'em-websocket'
require 'sinatra/base'
require 'thin'
require 'haml'

EventMachine.run do
  class App < Sinatra::Base
    get '/' do
      haml :index
    end
  end

  @connections = []
  EventMachine::WebSocket.start(:host => '0.0.0.0', :port => 3001) do |ws| 
    ws.onopen {
      @connections << ws
    }

    ws.onmessage { |msg|
      puts "got message #{msg}"
      @connections.each do |ws|
        puts "Sending to #{ws}"
        ws.send(msg)
      end
    }

    ws.onclose {
      @connections.delete(ws)
      ws.send "WebSocket closed"
    }

  end

  App.run!({:port => 3000})
end

