
require "socket"
require "./clock"
require "./messenger"

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


class Connection
  property address : String
  property port : Int32
  property host_name : String
  property host : Socket::IPAddress
  property history : PacketPool
  property last :  Int64
  property warnings : Int16

  def initialize(address : String, port : Int32)
    @address = address
    @port = port
    @host_name = "#{address}:#{port}"
    @host = Socket::IPAddress.new address, port
    @history = PacketPool.new 200
    @last = 0
    @warnings = 0
  end

  def initialize(host : Socket::IPAddress)
    @address = host.address
    @port = host.port
    @host_name = "#{host.address}:#{host.port}"
    @host = Socket::IPAddress.new host.address, host.port
    @history = PacketPool.new 200
    @last = 0
    @warnings = 0
  end

  def log(packet : Packet, time : Int64)
    @history.add packet
    @last = time
  end

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
  property connection : Connection
  property connections : Hash(Socket::IPAddress, Connection)
  property clock : Clock

  def initialize(address : String, port : Int32, clock : Clock)
    @socket = UDPSocket.new
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

  def recv
    begin
      puts "Server: recv"
      packet = Packet.new @socket.receive
      log packet
      return packet
    rescue err
      puts err.message
    end
  end

  def send(packet : Packet)
    begin
      puts "Server: Sending #{packet.data}"
      @socket.send packet.data, packet.host
      @connection.log packet, @clock.time
    rescue err
      puts err.message
    end
  end

  def send(data : String, host : Socket::IPAddress)
    packet = Packet.new data, host
    send packet
  end

  def sendall(data : String)
    puts "Server: Sending all #{data}"
    @connections.each_value do |con|
      send data, con.host
    end
  end

  def sendall(packet : Packet)
    sendall packet.data
  end

  def log(packet : Packet)
    if @connections.has_key? packet.host
      @connections[packet.host].log packet, @clock.time
    else
      @connections[packet.host] = Connection.new packet.host
    end
  end

  def log!(packet : Packet)
    @connections[packet.host].log packet, @clock.time
  end

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
  property input : Messenger(Packet)
  property output : Messenger(Packet)
  property network : Network
  property clock : Clock

  def initialize
    @input = Messenger(Packet).new
    @output = Messenger(Packet).new
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
  property input : Messenger(Packet)
  property output : Messenger(Packet)
  property network : Network
  property clock : Clock

  def initialize
    @input = Messenger(Packet).new
    @output = Messenger(Packet).new
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