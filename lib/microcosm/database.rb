
module Microcosm
  class Database
    attr_reader :cache

    def initialize
      super
      @cache = Cache.instance
    end

    def self.instance
      @instance ||= Rails.env.test? ? nil : new
    end

    def self.export(*args)
      self.instance.export(*args)
    end

    def export(*args)
      params = args[-1].is_a?(Hash) ? args[-1] : {}
      options = {
        limit: 10000,
        verbose: true,
        serialize: true,
        path: File.join(Rails.root,'db'),
        index: 0
      }.merge(params)
      index = options[:index] || 0
      objects = args.collect { |r|
        next r.limit(options[:limit]) if (r.is_a?(Class) && r.ancestors.include?(ApplicationRecord)) # Class objc
        next r if r.is_a?(ApplicationRecord) # object is active record
        next r.select {|rr| rr.is_a?(ApplicationRecord)} if r.is_a?(Array) # [object1,object2] array of records
      }.flatten.select {|r| r.present?}

      dataCache = args.select {|c| c.is_a?(Cache)}.first || self.cache
      options[:index] += 1

      objects.each do |row|
        # serialize row
        next if dataCache[row].present?
        puts "BEGIN: serializing class: #{row.class.name} id: #{row.id}" if options[:verbose]
        dataCache << row
        row.class.send(:reflect_on_all_associations,:belongs_to).each do |association|
          item = row.send(association.name)
          next unless item.present?
          puts "class: #{item.class.name} id:#{item.id} belongs_to:#{association.name}" if options[:verbose]
          export(item,dataCache,options)
        end

        row.class.send(:reflect_on_all_associations,:has_many).each do |association|
          items = row.send(association.name).limit(options[:limit])
          items.each do |i|
            puts "class: #{i.class.name} id:#{i.id} has_many:#{association.name}" if options[:verbose]
            export(i,dataCache,options)
          end
        end
        puts "END: serializing class: #{row.class} id: #{row.id} seq: #{index}" if options[:verbose]
      end

      dataCache.save(path:options[:path],verbose:options[:verbose]) if index == 0
      dataCache
    end


    def self.import(*args)
      self.instance.import(*args)
    end

    def import(*args)
      params = args[-1].is_a?(Hash) ? args[-1] : {}
      options = {
        path: File.join(Rails.root,"db"),
        verbose: true,
        purge: false,
        file: "*.yml",
        batch_size: 100,
        all_or_none: false,
        raise_error: true
      }.merge(params.select {|k,v| v.present?})
      import_path = File.join(options[:path],options[:file])
      import_items = lambda {|items|
        first = items&.first
        ActiveRecord::Base.transaction   do
          if first.present? && options[:purge]
            puts "PURGE model: #{first.class.name} items: #{first.class.count}" if options[:verbose]
            first.class.delete_all
          end

          first.class.import(items, batch_size: options[:batch_size],
                             all_or_none: options[:all_or_none], raise_error: options[:raise_error]) if items.present?

          puts "SAVED model: #{first.class.name} items: #{items.size} into database: #{first.class.connection.current_database}"  if options[:verbose]
        end if first.present?
      }

      Rails.application.eager_load!

      if import_path.ends_with?(".zip") && File.exists?(import_path) then
        Zip::File.open(import_path) do |zip|
          zip.each do |entry|
            if  entry.file? && entry.name.ends_with?(".yml")
              content = entry.get_input_stream.read
              items = YAML.load_stream(content)&.flatten
              import_items.call(items)
            end
          end
        end
        return
      end

      import_paths = Dir[File.join(options[:path],options[:file])].sort
      import_paths.each do |r|
        puts "IMPORT path: #{r}" if options[:verbose]
        items = YAML.load_file(r)
        import_items.call(items)
      end
      puts "DONE" if options[:verbose]
    end
  end

end