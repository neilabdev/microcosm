namespace :db do
  namespace :microcosm do
    desc "Import YML model files created with :export task"
    task import_yml: [:environment] do
      path = ENV['DIR'] or abort "usage: rake db:microcosm:import_yml DIR=path/to/yml/dir VERBOSE=0 PURGE=0 RESET=0"
      verbose = [1, '1', 'TRUE', 'true'].include? ENV['VERBOSE']
      purge = [1, '1', 'TRUE', 'true'].include? ENV['PURGE']
      file = ENV['FILE']
      reset = [1, '1', 'TRUE', 'true'].include? ENV['RESET'] # NOTE: Perhaps should default to true?

      Rails.logger.level = Logger::DEBUG if verbose
      Microcosm::Database.import(path: path, verbose: verbose, purge: purge, file: file)
      Rake::Task['db:microcosm:postgres:reset_sequence'].execute if reset
    end

    desc "Export Database Graph to YML files using all associated Models"
    task export: [:environment] do
      Rails.application.eager_load!
      klazz_criteria = ENV['CLASS'] or abort "usage: rake db:microcosm:export CLASS=<Model|all|Model[1,2,3]> [ LIMIT=<num> DIR=/path/to/export/dir ] [ EXCLUDE_FILE=/path/to/file ] [ EXCLUDE_TABLES=table1,table2 ]"
      limit = ENV['LIMIT'] || 500 #ID=User[13,34,23]
      path = ENV['DIR'] || Rails.root
      verbose = [1, '1', 'TRUE', 'true'].include? ENV['VERBOSE']
      resources = proc { |term|
        parts = term.split(/\|/).collect {|p| p.strip }
        results = []
        parts.each do |part|
          klass_ids_match = part.match(/(\w+)\[(.+)\]/)
          if klass_ids_match.present?
            (klass,klass_ids) = [Object.const_get(klass_ids_match[1]),klass_ids_match[2].strip]
            results.concat klass_ids == "*" ? klass.all : klass.find(klass_ids.split(/,/).collect {|i| i.strip })
          elsif ['*','all'].include?(term)
            results.concat ActiveRecord::Base.descendants
          else # jsut class name
            klass = Object.const_get(part)
            results.append klass
          end
        end
        results
      }.call(klazz_criteria)

      excluded_tables = ENV["EXCLUDE_TABLES"].to_s.split(",")
      excluded_file = ENV["EXCLUDE_FILE"].present?? File.read(ENV["EXCLUDE_FILE"]).split : []
      excludes = excluded_tables + excluded_file
      depth = ENV['DEPTH'].to_i
      Microcosm::Database.export(*resources, path: path, verbose: verbose, exclude: excludes, depth: depth, limit: limit)
    end

    desc "Reset database to db:schema:load in preparation for :import_yml"
    task reset: [:environment] do
      Rake::Task['db:drop'].execute
      Rake::Task['db:create'].execute
      Rake::Task['db:schema:load'].execute
    end

    desc "Print Dependency Graph"
    task print_graph: [:environment] do

      table_names = Microcosm::Util.models(table_names:true)
      table_names.each_with_index do |r,i|
        filename = ("%03d_#{r}.yml" % [i])
        puts "table_name: #{r} to file: #{filename}"
      end
    end


    desc 'Convert development DB to Rails test fixtures'
    task to_fixtures: :environment do
      TABLES_TO_SKIP = %w[ar_internal_metadata schema_migrations schema_info ].freeze

      begin
        ActiveRecord::Base.establish_connection
        ActiveRecord::Base.connection.tables.each do |table_name|
          next if TABLES_TO_SKIP.include?(table_name)

          conter = '000'
          file_path = "#{Rails.root}/test/fixtures/#{table_name}.yml"
          File.open(file_path, 'w') do |file|
            rows = ActiveRecord::Base.connection.select_all("SELECT * FROM #{table_name}")
            data = rows.each_with_object({}) do |record, hash|
              suffix = record['id'].blank? ? conter.succ! : record['id']

              safe_record = record.each_with_object({}) do |(key, value), hash|
                if rows.column_types[key].is_a?( ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb) then
                  hash[key] = value.is_a?(String) ? ( JSON.parse(value) rescue  {} ): value
                else
                  hash[key] = value
                end
              end

              hash["#{table_name.singularize}_#{suffix}"] = safe_record
            end
            puts "Writing table '#{table_name}' to '#{file_path}'"
            file.write(data.to_yaml)
          end
        end
      ensure
        ActiveRecord::Base.connection.close if ActiveRecord::Base.connection
      end
    end

    namespace :postgres do
      desc "stop"
      task stop: [:environment] do
        db_name = ENV['DATABASE'] || User.connection.current_database
        # thanks to http://stackoverflow.com/questions/12924466/capistrano-with-postgresql-error-database-is-being-accessed-by-other-users
        # previously, we were kill'ing the postgres processes: http://stackoverflow.com/questions/2369744/rails-postgres-drop-error-database-is-being-accessed-by-other-users
        # cmd = %(psql -c "SELECT procpid, pg_terminate_backend(procpid) as terminated FROM pg_stat_activity WHERE procpid <> pg_backend_pid();" -d '#{db_name}')
        cmd = %(psql -c "SELECT pid, pg_terminate_backend(pid) as terminated FROM pg_stat_activity WHERE pid <> pg_backend_pid();" -d '#{db_name}')
        puts "WARN: killing connections to #{db_name}."

        fail $?.inspect unless system(cmd)
      end

      desc "Reset Postgres PK sequences so autogenerated saves won't collide with existing record"
      task reset_sequence: [:environment] do
        ActiveRecord::Base.connection.tables.each do |t|
          ActiveRecord::Base.connection.reset_pk_sequence!(t)
        end
      end

      desc "List tables views (for excluding)"
      task print_views: [:environment] do
        puts Scenic.database.views.collect {|t| t.name }.uniq.sort
      end
    end
  end
end
