

class Event(T)
  property value : T
  property dest : Int32

  def initialize(@value, @dest)
  end
end


class EventPool(T)
  property events : Hash(Int32, Array(T))

  def initialize
    @events = Hash(Int32, Array(T)).new
  end

  def add(index : Int32, event : T)
    if !@events.has_key? index
      @events[index] = Array(T).new
    @events[index] << event
  end

  def get(index : Int32) : Array(T)
    if @events.has_key? index
      @events[index]
    else
      Array(T).new
    end
  end

  def get!(index : Int32) : Array(T)
    @events[index]
  end

  def del(index : Int32)
    @events.delete index
  end

end#class


class EventManager(T, S)
  property events : Array(Event(T))
  property subs : Hash(Int32, S)

  def initialize
    @events = Array(Event(T)).new
    @subs = Hash(Int32, S).new  
  end

  def sub(i : Int32, s : S)
    @subs[i] = s
  end

  def unsub(i : Int32)
    @subs.delete i
  end

  def send(event : Event(T))
    @events << event
  end

  def send!(event : Event(T))
    @subs[event.dest].notify event
  end

  def push
    events.items do |event|
      send! event
    end
  end

end#class

