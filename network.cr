require "socket"
require "./clock"


JOIN_Q = 0
JOIN_R = 1
AUTH_Q = 2
AUTH_R = 3
INPUT_Q = 4
INPUT_R = 5
SYNC_Q = 6
SYNC_R = 7
TICK_Q = 8
TICK_R = 9
INFO_Q = 10
INFO_R = 11
PART_Q = 12
PART_R = 13
ERR = 14


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


class Server
  property messages : PacketPool
  property clock : Clock
  property socket : UDPSocket
  property connections : Hash(Socket::IPAddress, Connection)
  property port : Int32
  property running : Bool

  #property connection : Connection

  def initialize(port : Int32)
    @messages = PacketPool.new 128
    @clock = Clock.new 10_000
    @connections = Hash(Socket::IPAddress, Connection).new
    @socket = UDPSocket.new
    @port = port
    @running = false

    #@connection = Connection.new("127.0.0.1", port)
  end

  def start
    puts "Server starting on 127.0.0.1:#{@port}"
    #@connection.bind
    @socket.bind("127.0.0.1", port)
    @running = true 

    spawn do
      while @running
        puts "Incoming fiber running"
        #packet = @connection.recv
        packet = Packet.new @socket.receive
        handle_incoming packet

        Fiber.yield
      end
    end
        
    spawn do
      while @running
        if @clock.tick?
          #puts "tick #{clock.time}"
          handle_outgoing
          #check_connections
        end

        Fiber.yield
      end
    end
  end

  def stop
    @running = false
  end

  def handle_incoming(packet : Packet)
    incoming_callback packet
    if @connections.has_key? packet.host
      handle_data packet
    else
      handle_join packet
    end
  end

  def incoming_callback(packet : Packet)
    #puts "Handling incoming"
  end

  def handle_join(packet : Packet)
    con = Connection.new packet.host
    @connections[packet.host] = con
    log packet
    join_callback packet
  end

  def join_callback(packet : Packet)
    #puts "Join from #{packet.host}"
  end

  def handle_data(packet : Packet)
    #@messages.send packet
    log packet
    data_callback packet
  end

  def data_callback(packet : Packet)
    #puts "#{packet.data} recv from #{packet.host}"
  end

  def handle_outgoing
    outgoing_callback
    sendall @clock.time.to_s
    #packet = @messages.receive?
    #while packet
    #    puts "Has packet"
    #    sendall(packet)
    #    packet = @messages.receive?
    #end
  end

  def outgoing_callback()
    #puts "Handling outgoing"
  end

  def send(packet : Packet)
    puts "Sending #{packet.data}"
    @socket.send packet.data, packet.host
    #@connections[packet.host].send(packet)
  end

  def send(data : String, host : Socket::IPAddress)
    puts "Sending #{data}"
    @socket.send data, host
    #@connections[host].send(data)
  end

  def sendall(data : String)
    puts "Sending all #{data}"
    @connections.each_value do |con|
      @socket.send data, con.host
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

    