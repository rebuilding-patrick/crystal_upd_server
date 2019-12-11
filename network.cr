
require "socket"
require "./physicr/clock"
require "./messenger"


PLAYER_IDENT = "0"
PLAYER_POS = "1"
PLAYER_BLOCK = "2"
PLAYER_MSG = "3"
PLAYER_ACTION = "4"
PLAYER_LEVEL = "5"

SERVER_IDENT = "50"
SERVER_POS = "51"
SERVER_PING = "52"
SERVER_LEVEL = "53"
SERVER_BLOCK = "54"
SERVER_NEW_ACTOR = "55"
SERVER_DEL_ACTOR = "56"
SERVER_MSG = "57"
SERVER_KICK = "58"
SERVER_LEVEL_END = "59" 

#eg b"1/150/100/join/0"
# 0 = time
# join = command
# 150/100/1 = args


#Not used, skipping in favor of using a message directly.
#Keeping around for general usage.
struct Packet
  property host : Socket::IPAddress
  property data : String

  def initialize(data : String, host : String, port : Int32)
    @data = data
    @host = Socket::IPAddress.new host, port
  end

  def initialize(data : String, host : Socket::IPAddress)
    @data = data
    @host = host
  end

  def initialize(data : Tuple(String, Socket::IPAddress))
    @data = data[0]
    @host = data[1]
  end
end#struct


#Not used right now
class PacketPool
  property size : Int32
  property index : Int32
  property pool : Array(Packet)

  def initialize(size : Int32)
    @size = size
    @index = -1
    @pool = Array(Packet).new
        
    null_packet = Packet.new("null", "0.0.0.0", 0)
    size.times do |i|
      @pool << null_packet
    end
  end

  def advance
    @index += 1
    if @index >= @size
      @index = 0
    end      
  end
    
  def get(index : Int32) : Packet
    @pool[index]
  end

  def get : Packet
    @pool[@index]
  end

  def set(index : Int32, packet : Packet)
    @pool[index] = packet
  end

  def add(packet : Packet)
    advance
    @pool[@index] = packet
  end
end#class


struct Message
  property host : Socket::IPAddress
  property data : String

  property time : Int64
  property command : String
  property args : Array(String)

  def initialize(@host, @data, @time, @command, @args)
  end
end#struct


class Parser
  def initialize(clock : Clock)
    @clock = clock
    @delimiter = "/"
    host = Socket::IPAddress.new "127.0.0.1", 0
    @bad_message = Message.new(host, "bad message", 0_i64, "-999", Array(String).new)
  end 

  def encode(command : String, data : String) : String
    return "#{data}/#{command}/#{@clock.time}"
  end

  def decode(packet : Tuple(String, Socket::IPAddress)) : Message
    begin
      data = packet[0].split @delimiter
      time = data.pop.to_i64
      command = data.pop
      return Message.new packet[1], packet[0], time, command, data
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
  #property history : PacketPool
  property last :  Int64
  property warnings : Int16

  def initialize(address : String, port : Int32)
    @address = address
    @port = port
    @host_name = "#{address}:#{port}"
    @host = Socket::IPAddress.new address, port
    #@history = PacketPool.new 200
    @last = 0
    @warnings = 0
  end

  def initialize(host : Socket::IPAddress)
    @address = host.address
    @port = host.port
    @host_name = "#{host.address}:#{host.port}"
    @host = Socket::IPAddress.new host.address, host.port
    #@history = PacketPool.new 200
    @last = 0
    @warnings = 0
  end

  # def log(packet : Packet, time : Int64)
  #   @history.add packet
  #   @last = time
  # end

  def check(time : Int64) : Int16
    if time - @last > 10
      @warnings += 1
    else
      @warnings = 0
    end
  end
        
end#class


class Network
  property socket : UDPSocket
  property parser : Parser
  property connection : Connection
  property connections : Hash(Socket::IPAddress, Connection)
  property clock : Clock

  def initialize(address : String, port : Int32, clock : Clock)
    @socket = UDPSocket.new
    @parser = Parser.new clock
    @connection = Connection.new address, port
    @connections = Hash(Socket::IPAddress, Connection).new
    @clock = clock
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
    return @parser.decode @socket.receive
  end

  def send(data : String, host : Socket::IPAddress)
    begin
      #puts "Server: Sending #{data} to #{host.address}:#{host.port}"
      @socket.send data, host
    rescue err
      puts "Server: Error sending #{data} : #{err.message}"
    end
  end

  def send(command : String, data : String, host : Socket::IPAddress)
    begin
      msg = @parser.encode command, data
      #puts "Server: Sending #{msg} to #{host}"
      @socket.send msg, host
    rescue err
      puts "Server: Error sending #{data} : #{err.message}"
    end
  end

  def sendall(command : String, data : String)
    msg = @parser.encode command, data
    sendall msg
  end

  def sendall(data : String)
    #puts "Server: Sending all #{data}"
    @connections.each_value do |con|
      send data, con.host
    end
  end

  # def log(packet : Packet)
  #   if @connections.has_key? packet.host
  #     @connections[packet.host].log packet, @clock.time
  #   else
  #     @connections[packet.host] = Connection.new packet.host
  #   end
  # end

  # def log!(packet : Packet)
  #   @connections[packet.host].log packet, @clock.time
  # end

  def check_connections
    puts "Server: Checking connections"
    dead = Array(Socket::IPAddress).new
    @connections.each_value do |con|
      warnings = con.check @clock.time
      if warnings > 2
        puts "Server: #{con.host} has timed out"
        dead << con.host
      elsif warnings > 0
        puts "Server: Timeout warning for #{con.host}"
      end
    end

    dead.each do |host|
      @connections.delete host
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