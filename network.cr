
require "socket"

require "./messenger"
require "./clock"


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

  #property socket : UDPSocket

  def initialize(address : String, port : Int32)
    @address = address
    @port = port
    @host_name = "#{address}:#{port}"
    @host = Socket::IPAddress.new address, port
    @history = PacketPool.new 200
    @last = 0
    @warnings = 0

    #@socket = UDPSocket.new
  end

  def initialize(host : Socket::IPAddress)
    @address = host.address
    @port = host.port
    @host_name = "#{host.address}:#{host.port}"
    @host = Socket::IPAddress.new host.address, host.port
    @history = PacketPool.new 200
    @last = 0
    @warnings = 0

    #@socket = UDPSocket.new
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


class Client
  property incoming : Messenger(Packet)
  property outgoing : Messenger(Packet)
  property connection : Connection | Nil
  property clock : Clock
  property socket : UDPSocket
  property running : Bool

  def initialize
    @incoming = Messenger(Packet).new
    @outgoing = Messenger(Packet).new
    @connection = nil
    @clock = Clock.new 10_000
    @socket = UDPSocket.new
    @running = false
  end

  def connect(address : String, port : Int32)
    @connection = Connection.new address, port
  end

  def connect(host : Tuple(String, Int32))
    @connection = Connection.new host[0], host[1]
  end

  def connect(host : Socket::IPAddress)
    @connection = Conneciton.new host.address, host.port
  end

  def run
    puts "Client: Waiting for data"
    @running = true

    spawn do
      while @running
        packet = Packet.new @socket.receive
        _handle_incoming packet

        Fiber.yield
      end
    end
        
    spawn do
      while @running
        if @clock.tick?
          _handle_outgoing
        end

        Fiber.yield
      end
    end
  end

  def _handle_input(packet : Packet)
    @incoming.send packet
    handle_input packet
  end

  def handle_input(packet : Packet)
    puts "Input: #{packet.data}"
  end

  def _handle_output(outgoing : Array(Packet))
    outgoing.each do |packet|
      send packet
    end
    handle_output outgoing
  end

  def handle_output(outgoing)
   puts "Output: #{outgoing}"
  end
  
  def send(packet)
    @connection.log packet, @clock.time
    @socket.send packet.data, packet.host
  end

  def send(self, data)
    @connection.log packet, @clock.time
    @socket.send data, @connection.host
  end

end#class


class Server
  #TODO add a banned list
  #TODO add a callback for sending
  #TODO handle parting clients
  property joining : Messenger(Packet)
  property incoming : Messenger(Packet)
  property outgoing : Messenger(Packet)
  property messages : PacketPool
  property clock : Clock
  property socket : UDPSocket
  property connections : Hash(Socket::IPAddress, Connection)
  property port : Int32
  property password : String
  property running_out : Bool
  property running_in : Bool

  def initialize(port : Int32, password : String)
    @joining = Messenger(Packet).new
    @incoming = Messenger(Packet).new
    @outgoing = Messenger(Packet).new
    
    @messages = PacketPool.new 128
    @clock = Clock.new 10_000
    @connections = Hash(Socket::IPAddress, Connection).new
    @socket = UDPSocket.new
    @port = port
    @password = password
    @running_in = false
    @running_out = false

  end

  def start
    connect
    start_in
    start_out
  end

  def start_input
    @running_in = true
    spawn do
      while @running_in
        _handle_incoming
        Fiber.yield
      end
    end
  end

  def start_output
    @running_out = true
    spawn do
      while @running_out
        if @clock.tick?
          _handle_outgoing
        end
        Fiber.yield
      end
    end
  end

  def stop
    @running_in = false
    @running_out = false
  end

  def connect
    begin
      puts "Server starting on 127.0.0.1:#{@port}"
      @socket.bind("127.0.0.1", port)
      @running = true 
    rescue err
      puts err.message
      return false
    end
  end

  def _handle_incoming
    packet = Packet.new @socket.receive
    handle_incoming packet
    if @connections.has_key? packet.host
      _handle_data packet
    else
      _handle_join packet
    end
  end

  #Callback function to be overridden
  def handle_incoming(packet : Packet)
    puts "Handling incoming"
  end

  def _handle_join(packet : Packet)
    begin
      if packet.data == @password
        con = Connection.new packet.host
        @connections[packet.host] = con
        @joining.send packet
        log packet
        handle_join packet
      else
        _handle_reject packet
      end
    rescue err
      puts err.message
    end
  end

  def _handle_reject(packet : Packet)
    handle_reject packet
  end

  #Callback function to be overridden
  def handle_join(packet : Packet)
    puts "Join from #{packet.host}"
  end

  #Callback function to be overrideen
  def handle_reject(packet : Packet)
    puts "Join rejected from #{packet.host}"

  end 

  def _handle_data(packet : Packet)
    begin
      @incoming.send packet
      log packet
      handle_data packet
    rescue err
      puts err.message
    end
  end

  #Callback function to be overridden
  def handle_data(packet : Packet)
    puts "#{packet.data} recv from #{packet.host}"
  end

  def _handle_outgoing
    begin
      outgoing = @outgoing.get
      handle_outgoing outgoing
      outgoing.each do |packet|
        send packet
      end
    rescue err
      puts err.message
    end
  end

  def handle_outgoing(outgoing : Array(Packet))
    #puts "Handling outgoing #{@clock.time}"
  end

  def send(packet : Packet)
    begin
      puts "Sending #{packet.data}"
      @socket.send packet.data, packet.host
    rescue err
      puts err.message
    end
  end

  def send(data : String, host : Socket::IPAddress)
    begin
      puts "Sending #{data}"
      @socket.send data, host
    rescue err
      puts err.message
    end
  end

  def sendall(data : String)
    puts "Sending all #{data}"
    @connections.each_value do |con|
      send data, con.host
      #connection.send(data, con.host)
      #@connection.send(data, connection.host)
    end
  end

  def sendall(packet : Packet)
    sendall packet.data
  end

  def log(packet : Packet)
    @connections[packet.host].log packet, @clock.time
  end

  def check_connections
    puts "Server: Checking connections"
    dead = Array(Socket::IPAddress).new
    time = @clock.time
    @connections.each_value do |con|
      warnings = con.check time
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

