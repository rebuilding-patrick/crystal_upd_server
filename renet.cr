
require "socket"


ERR = 4
JOIN = 3
AWK = 2
RELIABLE = 1
UNRELIABLE = 0


struct Packet
  property host : Socket::IPAddress
  property data : String

  def initialize(@host, @data)
  end

  def initialize(@data, @host)
  end
end


struct Message
  property index : Int32
  property command : Int32
  property args : Array(String)

  property host : Socket::IPAddress
  property data : String

  def initialize(@index, @command, @args, packet : Packet)
    @host = packet.host
    @data = packet.data
  end

  def initialize(@index, @command, @args, packet : Tuple(String, Socket::IPAddress))
    @host = packet[1]
    @data = packet[0]
  end

  def initialize(@index, @command, @args, @host, @data)
  end
end


class Parser
  def initialize()
    @delimiter = "/"
    host = Socket::IPAddress.new "127.0.0.1", 0
    @bad_message = Message.new(0, ERR, Array(String).new, host, "-999")
  end 

  def encode(data, command, index) : String
    return "#{data}/#{command}/#{index}"
  end

  def decode(data : String, host : Socket::IPAddress) : Message
    begin
      values = data.split @delimiter
      index = values.pop.to_i
      command = values.pop.to_i
      return Message.new index, command, values, host, data
    rescue err
      puts "Network: Error parsing packet #{data} from #{host} - #{err.message}"
      return @bad_message
    end
  end

  def decode(packet : Tuple(String, Socket::IPAddress)) : Message
    return decode packet[0], packet[1]
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

  property index : Int32
  property resending : Hash(Int32, String)
  property message_buffer : Array(String)
  property buffer_len : Int32
  property buffer_size : Int32
  property buffer_max : Int32
  property delimiter : String

  def initialize(address : String, port : Int32)
    @address = address
    @port = port
    @host_name = "#{address}:#{port}"
    @host = Socket::IPAddress.new address, port

    @index = 0
    @resending = Hash(Int32, String).new
    @message_buffer = ["", "", "", "", ""] of String
    @buffer_max = 4
    @buffer_len = -1
    @buffer_size = 0
    @delimiter = "|"
  end

  def initialize(host : Socket::IPAddress)
    @address = host.address
    @port = host.port
    @host_name = "#{host.address}:#{host.port}"
    @host = Socket::IPAddress.new host.address, host.port

    @index = 0
    @delimiter = "|"
    @resending = Hash(Int32, String).new
    @message_buffer = ["", "", "", "", ""] of String
    @buffer_max = 4
    @buffer_len = -1
    @buffer_size = 0
  end

  def buffer(data : String, command : Int32)
    @index += 1
    parsed_data = "#{data}/#{command}/#{@index}"
    if command == RELIABLE || command == JOIN
      @resending[@index] = parsed_data
    end
    buffer_data(parsed_data)
  end

  def buffer_data(data : String)
    size = data.size
    if @buffer_size + size > 768
      @buffer_size = 0
      @buffer_len += 1
    else
      if @buffer_len < 0
        @buffer_len = 0
      end

      if buffer_size > 0
        @message_buffer[@buffer_len] += @delimiter
        size += 1
      end
    end
    @message_buffer[@buffer_len] += data
    @buffer_size += size
    #TODO handle buffer overflow
  end

  def flush()
    i = 0
    while i <= @buffer_max
      @message_buffer[i] = ""
      i += 1
    end
    @buffer_len = -1
    @buffer_size = 0
  end

  def confirm(index : Int32)
    if @resending.has_key? index
      @resending.delete index
    end
  end

end#class


class Network
  property socket : UDPSocket
  property parser : Parser
  property connection : Connection
  property connections : Hash(Socket::IPAddress, Connection)
  property delimiter : String

  def initialize(address : String, port : Int32)    
    @socket = UDPSocket.new
    @parser = Parser.new
    @connection = Connection.new address, port
    @connections = Hash(Socket::IPAddress, Connection).new
    @delimiter = "|"
  end

  def bind
    begin
      puts "Server: Starting on #{@connection.host_name}"
      @socket.bind @connection.host
    rescue err
      puts err.message
    end
  end

  def recv : Array(Message)
    packet = @socket.receive
    host = packet[1]
    data = packet[0].split @delimiter
    messages = Array(Message).new
    data.each do |value|
      message = @parser.decode value, host

      if message.command == AWK
        connection.confirm message.index

      elsif message.command == RELIABLE
        messages << message
        send "0/#{AWK}/#{message.index}", message.host

      elsif message.command == UNRELIABLE
        messages << message
        
      elsif message.command == JOIN
        if @connections.has_key? message.host
          send "0/#{AWK}/#{message.index}", message.host
          @connections[host].confirm message.index
        else
          @connections[message.host] = Connection.new message.host
          messages << message
          send "0/#{JOIN}/#{message.index}", message.host
          #TODO this should go to a network.handle_join(message)
        end

      else
        puts "bad message command #{message.command}..."
      end
    end
    return messages
  end

  def buffer(data : String, host : Socket::IPAddress, command : Int32 = UNRELIABLE)
    @connections[host].buffer(data, command)
  end

  def flush
    @connections.each do |connection|
      connection.flush
    end
  end

  def send
    @connections.each do |connection|
      send connection
    end
  end

  #Sends the contents of the connection's message buffer immediately
  def send(connection : Connection)
    i = 0
    while i <= connection.buffer_len
      send connection.message_buffer[i], connection.host
      connection.message_buffer[i] = ""
      i += 1
    end
    connection.buffer_len = -1
    connection.buffer_size = 0
  end

  def send(data : String, host : Socket::IPAddress)
    begin
      #puts "Server: Sending #{data} to #{host.address}:#{host.port}"
      @socket.send data, host
    rescue err
      puts "Server: Error sending #{data} : #{err.message}"
    end
  end

  def resend()
    @connections.each do |connection|
      resend connection
    end
  end

  def resend(connection : Connection)
    connection.resending.each_value do |data|
      send data, connection.host
    end
  end

end#class
