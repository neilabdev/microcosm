module Microcosm
  class Util
    def self.models(*args)
      params = args[-1].is_a?(Hash) ? args[-1] : {}
      options = {
        table_names: false
      }.merge(params)

      Rails.application.eager_load!
      class_cache = ActiveRecord::Base.descendants.collect {|c| [c.name,c]}.to_h
      children = {}
      make_mapping = lambda { |klazz|
        {
          belongs_to: klazz.send(:reflect_on_all_associations, :belongs_to).collect { |r| #child
            next nil if r.options[:polymorphic] #|| r.options[:through]

            begin
              (children[r.class_name] ||= []).push(klazz)
              # class_cache[r.class_name]
            rescue Exception => e
              next nil
            end
          }.select { |k| k.present? },
          has_many: klazz.send(:reflect_on_all_associations, :has_many).collect { |r|
            begin
              class_cache[r.class_name].presence || r.klass   unless r.options[:polymorphic]  #|| r.options[:through]
            rescue Exception => e
              next nil # for a bogus hasy_many
            end
          }.select { |k| k.present? },
          type: klazz,
          children: (children[klazz.name] ||= [])
        }
      }

      unsorted_descendants = ActiveRecord::Base.descendants
      mappings = Hash[unsorted_descendants.collect { |d| [d.name, make_mapping.call(d)] }   ]
      resolved_dependencies = []
      stacked_dependencies = []
      deep_resolve = lambda { |klazzees, resolved, stacked|
        for klazz in klazzees.flatten do
          for parent in (mappings.dig(klazz.name,:belongs_to) || []).flatten.uniq # [klazz.name][:belongs_to]
            is_resolved =  resolved.include?(parent) || stacked.include?(parent)
            unless is_resolved then
              stacked.push(parent)
              deep_resolve.call([parent], resolved,stacked)
              stacked.pop
            end
          end
          resolved.push(klazz) unless resolved.include?(klazz)
        end
        resolved
      }

      resolved_descendants = deep_resolve.call(unsorted_descendants, resolved_dependencies,stacked_dependencies)

      options[:table_names] ?
        resolved_descendants.collect { |t| t.table_name } :
        resolved_descendants
    end
  end
end