require 'activerecord-import'

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

    def fmt_exception(exception,backtrace:nil)
      exception.message.split("\n").collect{|t|t.strip}.select{|s|s.present?}.join("\\n")
    end

    def self.export(*args)
      self.instance.export(*args)
    end

    def export(*args,**kwargs)
      options = {
        limit: 10000,
        verbose: true,
        serialize: true,
        exclude: [],
        path: File.join(Rails.root,'db'),
        index: 0,
        depth: 0
      }.merge(kwargs.select {|k,v| v.present?})
      index = options[:index] || 0
      excluded_tables = options[:exclude]
      objects = args.collect { |r|
        is_activerecord_model = r.is_a?(Class) && r.ancestors.include?(ActiveRecord::Base)
        next nil if is_activerecord_model && excluded_tables.include?(r.table_name)
        next nil if r.respond_to?(:abstract_class) && r.abstract_class

        begin
          next r.limit(options[:limit]).to_a
        rescue  Exception => e
          puts "failed: loading class: #{r.is_a?(Class) ? r.name: r } because: \"#{fmt_exception(e)}\""   if options[:verbose]
          next nil
        end if (is_activerecord_model && !r.abstract_class) # Class objc
        next r if is_activerecord_model # object is active record
        next r.select {|rr| rr.ancestors.include?(ActiveRecord::Base) && !rr.abstract_class } if r.is_a?(Array) # [object1,object2] array of records
      }.flatten.select {|r| r.respond_to?(:abstract_class) && r.abstract_class ? false :r.present?}

      dataCache = args.select {|c| c.is_a?(Cache)}.first || self.cache
      options[:index] += 1

      objects.each do |row|
        # serialize row
        next if dataCache[row].present?
        puts "BEGIN: serializing class: #{row.class.name} id: #{row.id}" if options[:verbose]
        dataCache << row

        row.class.send(:reflect_on_all_associations,:belongs_to).each do |association|
          begin
            item = row.send(association.name)
            next unless item.present?
            puts "class: #{item.class.name} id:#{item.id} belongs_to:#{association.name}" if options[:verbose]
            export(item,dataCache,options)
          rescue Exception => e
            puts "failed: class: #{row.class.name}  belongs_to:#{association.name} because: #{fmt_exception(e)}" if options[:verbose]
          end
        end

        row.class.send(:reflect_on_all_associations,:has_one).each do |association|
          begin
            item = row.send(association.name)
            next unless item.present?
            puts "class: #{item.class.name} id:#{item.id} has_one:#{association.name}" if options[:verbose]
            export(item,dataCache,options)
          rescue Exception => e
            puts "failed: class: #{row.class.name} has_one:#{association.name} because: #{fmt_exception(e)}"  if options[:verbose]
          end
        end

        row.class.send(:reflect_on_all_associations,:has_many).each do |association|
          begin
            items = row.send(association.name).limit(options[:limit])
            puts "class: #{row.class.name} retrieving associations:#{association.name} with limit: #{options[:limit]}" if options[:verbose]
            items.each do |i|
              puts "class: #{i.class.name} id:#{i.id} has_many:#{association.name}" if options[:verbose]
              export(i,dataCache,options)
            end
          rescue  Exception => e
            puts "failed: class: #{row.class.name} has_many:#{association.name} because: #{fmt_exception(e)}"  if options[:verbose]
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

    def import(*args,**kwargs)
      options = {
        path: File.join(Rails.root,"db"),
        verbose: true,
        purge: false,
        file: "*.yml",
        batch_size: 100,
        all_or_none: false,
        raise_error: true
      }.merge(kwargs.select {|k,v| v.present?})

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

    private

    def fmt_exception(exception,backtrace:nil)
      exception.message.split("\n").collect{|t|t.strip}.select{|s|s.present?}.join("\\n")
    end
  end

end