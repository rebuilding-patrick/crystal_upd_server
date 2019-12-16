
require "socket"
require "./physicr/clock"

require "./messenger" #This is for the client and server classes not the network component.

CONFIRM = "99"

PLAYER_IDENT = "0"
PLAYER_POS = "1"
PLAYER_BLOCK = "2"
PLAYER_MSG = "3"
PLAYER_ACTION = "4"
PLAYER_LEVEL = "5"

SERVER_IDENT = "50"
SERVER_POS = "51"
SERVER_PING = "52" #This isn't being used due to constant communication. Remove?
SERVER_LEVEL = "53" #This is new level information
SERVER_BLOCK = "54" #This is block change information, usually from other players
SERVER_NEW_ACTOR = "55"
SERVER_DEL_ACTOR = "56"
SERVER_MSG = "57"
SERVER_KICK = "58"
SERVER_LEVEL_END = "59"

#eg b"1/150/100/join/0"
# item[-1] 0 = time
# item[-2] join = command
# item[0] 150/100/1 = args

struct Packet
  property host : Socket::IPAddress
  property data : String

  def initialize(@host, @data)
  end
end


struct Message
  property host : Socket::IPAddress
  property data : String

  property time : Int64
  property index : Int32
  property command : String
  property args : Array(String)

  def initialize(@host, @data, @time, @index, @command, @args)
  end
end#struct


class MessagePool
  property size : Int32
  property index : Int32
  property pool : Array(Message)

  def initialize(size : Int32)
    @size = size
    @index = -1
    @pool = Array(Message).new
    
    null_ip = Socket::IPAddress.new("0.0.0.0", 0)
    null_args = Array(String).new
    null_msg = Message.new(null_ip, "null", -1_i64, 0, "null", null_args)

    size.times do |i|
      @pool << null_msg
    end
  end

  def advance
    @index += 1
    if @index >= @size
      @index = 0
    end      
  end
    
  def get(index : Int32) : Message
    @pool[index]
  end

  def get : Message
    @pool[@index]
  end

  def set(index : Int32, message : Message)
    @pool[index] = message
  end

  def add(message : Message)
    advance
    @pool[@index] = message
  end
end#class


class Parser
  def initialize(clock : Clock)
    @clock = clock
    @delimiter = "/"
    host = Socket::IPAddress.new "127.0.0.1", 0
    @bad_message = Message.new(host, "bad message", 0_i64, 0, "-999", Array(String).new)
  end 

  def encode(command : String, data : String) : String
    return "#{data}/#{command}/0/#{@clock.time}"
  end

  def encode(command : String, data : String, index : Int32) : String
    return "#{data}/#{command}#{index}#{clock.time}"
  end

  def decode(packet : Tuple(String, Socket::IPAddress)) : Message
    begin
      data = packet[0].split @delimiter
      time = data.pop.to_i64
      index = data.pop.to_i32
      command = data.pop
      return Message.new packet[1], packet[0], time, index, command, data
    rescue err
      puts "Network: Error parsing packet #{packet[0]} from #{packet[1]} - #{err.message}"
      return @bad_message
    end
  end

end#class


class Connection
  property address : String
  property port : Int32
  property host_name : String
  property host : Socket::IPAddress
  property history : MessagePool
  property last :  Int64
  property warnings : Int16

  def initialize(address : String, port : Int32)
    @address = address
    @port = port
    @host_name = "#{address}:#{port}"
    @host = Socket::IPAddress.new address, port
    @history = MessagePool.new 200
    @last = 0
    @warnings = 0
  end

  def initialize(host : Socket::IPAddress)
    @address = host.address
    @port = host.port
    @host_name = "#{host.address}:#{host.port}"
    @host = Socket::IPAddress.new host.address, host.port
    @history = MessagePool.new 200
    @last = 0
    @warnings = 0
  end

  def log(message : Message)
    @history.add message
    @last = message.time
  end

  def check(time : Int64) 
    #puts "Connection: Checking connection #{time} - #{@last}, (#{time - @last}) (#{time - @last}) > 5})"
    if time - @last > 5
      @warnings += 1
      puts "Warning #{@warnings}..."
      return @warnings
    else
      @warnings = 0
      return @warnings
    end
  end
        
end#class


class Network
  property socket : UDPSocket
  property parser : Parser
  property connection : Connection
  property connections : Hash(Socket::IPAddress, Connection)
  property clock : Clock
  property resending : Hash(Int32, Packet)
  property index : Int32

  def initialize(address : String, port : Int32, clock : Clock)
    @socket = UDPSocket.new
    @parser = Parser.new clock
    @connection = Connection.new address, port
    @connections = Hash(Socket::IPAddress, Connection).new
    @clock = clock

    @resending = Hash(Int32, Packet).new
    @index = 0
  end

  def bind
    begin
      puts "Server: Starting on #{@connection.host_name}"
      @socket.bind @connection.host
    rescue err
      puts err.message
    end
  end

  def recv : Message
    message = @parser.decode @socket.receive
    if message.index > 0
      if @resending.has_key? message.index
        @resending.delete message.index
      end
    end
    return message
  end

  def send(data : String, host : Socket::IPAddress)
    begin
      #puts "Server: Sending #{data} to #{host.address}:#{host.port}"
      @socket.send data, host
    rescue err
      puts "Server: Error sending #{data} : #{err.message}"
    end
  end

  def promise(command : String, data : String, host : Socket::IPAddress)
    @index += 1
    @resending[@index] = Packet.new host, @parser.encode(command, data, @index)
  end

  def send(command : String, data : String, host : Socket::IPAddress)
    msg = @parser.encode command, data
    send msg, host
  end

  def sendall(data : String)
    #puts "Server: Sending all #{data}"
    @connections.each_value do |con|
      send data, con.host
    end
  end

  def sendall(command : String, data : String)
    msg = @parser.encode command, data
    sendall msg
  end

  def resend
    @resending.each_value do |packet|
      send packet.data, packet.host
    end
  end

end#class


class Server
  property input : Messenger(Message)
  property output : Messenger(Message)
  property network : Network
  property clock : Clock

  def initialize
    @input = Messenger(Message).new
    @output = Messenger(Message).new
    @clock = Clock.new 1000
    @network = Network.new "127.0.0.1", 45456, @clock
  end

  def start
    @server.bind

    spawn do
      while true
        get_input
        Fiber.yield
      end
    end

    spawn do
      while true
        delta = @clock.tick
        if delta > 0.0
          handle_input 
          handle_output
        end
        Fiber.yield
      end
    end
  end

  def get_input
    packet = @network.recv
    if packet
      @input.send packet
    end
  end

  def handle_input
    packets = @input.get
    packets.each do |packet|
      @outgoing.send packet
    end
  end

  def handle_output
    packets = @output.get
    packets.each do |packet|
      @network.send packet
    end
  end

end#class


class Client
  property input : Messenger(Message)
  property output : Messenger(Message)
  property network : Network
  property clock : Clock

  def initialize
    @input = Messenger(Message).new
    @output = Messenger(Message).new
    @clock = Clock.new 1000
    @network = Network.new "127.0.0.1", 45456, @clock
  end

  def start
    spawn do
      while true
        get_input
        Fiber.yield
      end
    end

    spawn do
      while true
        delta = @clock.tick
        if delta > 0.0
          handle_input 
          handle_output
        end
        Fiber.yield
      end
    end
  end

  def get_input
    packet = @network.recv
    if packet
      @input.send packet
    end
  end

  def handle_input
    packets = @input.get
    packets.each do |packet|
      @outgoing.send packet
    end
  end

  def handle_output
    packets = @output.get
    packets.each do |packet|
      @network.send packet
    end
  end

end#class