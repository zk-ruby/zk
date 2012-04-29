class EventCatcher < Struct.new(:created, :changed, :deleted, :child, :all)
    
  def initialize(*args)
    super

    [:created, :changed, :deleted, :child, :all].each do |k|
      self.__send__(:"#{k}=", []) if self.__send__(:"#{k}").nil?
    end
  end
end

