module Microcosm
  class Cache
    attr_reader :data

    def self.instance
      @instance ||= new
    end

    def initialize
      super
      @errors ||= {}
      @data ||= {}
    end

    def addError(object,message: nil)

    end

    def add(object)
      if object.is_a?(ActiveRecord::Base)
        table_name = object.class.table_name
        data[table_name]||={}
        data[table_name][object.id] = object
      elsif object.is_a?(Array)
        object.each {|o| add(o) }
      end
    end

    def save(params={})
      options = {
        path: File.join(Rails.root,"db"),
        verbose: true,
      }.merge(params)

      table_names = Microcosm::Util.models(table_names:true)
      # FIXME: sometimes table_names doesn't contain all keys
      data.keys.sort {|t1,t2|
        (a,b) = [ table_names.index(t1), table_names.index(t2)]
        next a <=> b unless a.nil? || b.nil?
        next -1 if b.nil?
        next 1 if a.nil?
        0
      }.each_with_index do |r,i|
        filename = File.absolute_path(File.join(options[:path],"%03d_#{r}.yml" % [i]),Rails.root)
        puts "SAVING table_name: #{r} to file: #{filename}" if options[:verbose]
        File.open(filename, "w"){ |o| o.write(data[r].values.to_yaml)  }
      end
    end

    def [](key)
      return data[key]  unless key.is_a?(ActiveRecord::Base)
      object_id = key.is_a?(ActiveRecord::Base) ? key.id : nil
      object_class = key.is_a?(ActiveRecord::Base) ? key.class.table_name : nil
      data[object_class]&.fetch(object_id,nil)
    end

    def <<(object)
      add(object)
    end
  end

end