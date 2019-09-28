require "socket"

class Clock
    property rate : Time::Span
    property value : Int64
    property last : Time::Span

    def initialize(rate : Int64)
        #@rate = Time::Span.new(nanoseconds: rate * 10000000)
        @rate = Time::Span.new(0, 0, 1)

        @value = 0
        @last = Time.monotonic
    end

    def tick
        results = false
        current_time = Time.monotonic()
        if current_time - @last > @rate
            results = true
            @last = current_time
            @value += 1
        end

        results
    end
end


struct Packet
    property host : Socket::IPAddress
    property data : String

    def initialize(data : String, host : String, port : Int32)
        @data = data
        @host = Socket::IPAddress.new(host, port)
    end

    def initialize(data : String, host : Socket::IPAddress)
        @data = data
        @host = host
    end

    def initialize(data : Tuple(String, Socket::IPAddress))
        @data = data[0]
        @host = data[1]
    end
end


class PacketPool
    property size : Int32
    property index : Int32
    property pool : Array(Packet)

    def initialize(size : Int32)
        @size = size
        @index = -1
        @pool = Array(Packet).new
        
        null_packet = Packet.new("null", "0.0.0.0", 0)
        (0..size).each do |i|
            @pool << null_packet
        end
    end

    def advance
        @index += 1
        if @index >= @size
            @index = 0
        end
    end
    
    def get(index : Int32)
        @pool[index]
    end

    def get
        @pool[@index]
    end

    def set(index : Int32, packet : Packet)
        @pool[index] = packet
    end

    def add(packet : Packet)
        advance
        @pool[@index] = packet
    end
end


class Connection
    property address : String
    property port : Int32
    property host_name : String
    property host : Socket::IPAddress
    property socket : UDPSocket
    property history : PacketPool

    def initialize(address : String, port : Int32)
        @address = address
        @port = port
        @host_name = "#{address}:#{port}"
        @host = Socket::IPAddress.new(address, port)
        @socket = UDPSocket.new
        @history = PacketPool.new(200)
    end

    def initialize(host : Socket::IPAddress)
        @address = host.address
        @port = host.port
        @host_name = "#{host.address}:#{host.port}"
        @host = Socket::IPAddress.new(host.address, host.port)
        @socket = UDPSocket.new
        @history = PacketPool.new(200)
    end

    def bind
        @socket.bind(@address, @port)
    end

    def send(packet : Packet)
        begin
            @socket.send(packet.data, packet.host)
            @history.add(packet)
            puts "Sent #{packet.data}:#{packet.host.address}:#{packet.host.port}"
        rescue
            puts "Failed to send"
        end
    end

    def send(data : Tuple(String, Socket::IPAddress))
        packet = Packet.new(data[0], data[1])
        send(packet)
    end

    def send(data : String, host : Socket::IPAddress)
        packet = Packet.new(data, host)
        send(packet)
    end

    def send(data : String)
        packet = Packet.new(data, @host)
        send(packet)
    end

    def recv
        data, host = @socket.receive
        puts "Recv #{data}:#{host}"
        Packet.new(data, host)
    end
end


class Server
    property channel : Channel(Packet)
    property clock : Clock
    property connection : Connection
    property connections : Hash(Socket::IPAddress, Connection)
    property port : Int32

    def initialize(port : Int32)
        @channel = Channel(Packet).new
        @clock = Clock.new(1)
        @connections = Hash(Socket::IPAddress, Connection).new
        @connection = Connection.new("127.0.0.1", port)
        @port = port
    end

    def start
        puts "Server starting on 127.0.0.1:#{@port}"
        @connection.bind

        spawn do
            while true
                packet = @connection.recv
                handle_incoming(packet)

                Fiber.yield
            end
        end
        
        spawn do
            while true
                if @clock.tick
                    puts "tick #{clock.value}"
                    handle_outgoing
                end

                Fiber.yield
            end
        end
    end

    def handle_incoming(packet : Packet)
        puts "Handling incoming"
        if @connections.has_key?(packet.host)
            handle_data(packet)
        else
            handle_join(packet)
        end
    end

    def handle_join(packet : Packet)
        conn = Connection.new(packet.host)
        @connections[packet.host] = conn
        puts "Join from #{packet.host}"
    end

    def handle_data(packet : Packet)
        @channel.send(packet)
        puts "#{packet.data} recv from #{packet.host}"
    end

    def handle_outgoing
        puts "Handling outgoing"

        packet = @channel.receive?
        while packet
            puts "Has packet"
            sendall(packet)
            packet = @channel.receive?
        end
    end

    def send(packet : Packet)
        puts "Sending"
        @connections[packet.host].send(packet)
    end

    def send(data : String, host : Socket::IPAddress)
        puts "Sending"
        @connections[host].send(data)
    end

    def sendall(data : String)
        puts "Sending all"
        @connections.each_value do |connection|
            #connection.send(data, connection.host)
            @connection.send(data, connection.host)
        end
    end

    def sendall(packet : Packet)
        sendall(packet.data)
    end

end

    #         connections = @connections
    #         for host in connections:
    #             messages = @output_channel.get(host)
    #             for message in messages:
    #                 connections[host].send(message)
    #             end
    #         end

    #         #except:
    #         #    print('Connection Error')

    #         time.sleep(0.001)
    #     end
    # end

    # def confirm(host)
    #     @connections[host].confirm(@clock.get_value())
    # end

    # def check_connections
    #     print('Server: Checking connections')
    #     healthy_connections = {}

    #     for host in @connections:
    #         connection = @connections[host]
    #         if connection.check_connection(@clock.get_value()) < CONNECTION_WARN_RATE:
    #             healthy_connections[host] = connection
    #         else:
    #             connection.timeout_warnings += 1
    #             if connection.timeout_warnings < TIMEOUT_WARNINGS_TO_KILL:
    #                 print('Server: Timeout warning from %s:%s' % host)
    #                 healthy_connections[host] = connection
    #             else:
    #                 print('Server: Disconnect from %s:%s' % host)
    #             end
    #         end
    #     end

    #     @connections = healthy_connections
    # end

    # def add(host)
    #     conn = Connection(host)
    #     @connections[host] = conn
    #     return conn
    # end

    # def get(host)
    #     return @connections[host]
    # end

    # def has(host)
    #     return host in @connections
    # end

    # def getall
    #     return @connections
    # end

    # def get_message(tick, command, value, host)
    #     return @connections[host].message_pool.get(tick, command, value, host)
    # end

    # def send( message)
    #     message.index = @clock.get_value()
    #     @connections[message.host].send(message)
    # end

    # def send_value(command, value, host)
    #     index = @clock.get_value()
    #     @connections[host].send_value(index, command, value)
    # end




class Client
    property connection : Connection

    def initialize(address : String, port : Int32)
        @connection = Connection.new(address, port)
    end
end


puts "Starting"
server = Server.new(99887)
server.start

while true
    Fiber.yield
end

# spawn do
#     while true
#         pkt = conn.recv
#         conn.send(pkt)
#         #puts "Server echo #{pkt.data}"
#     end
# end

# while true
#     Fiber.yield
# end