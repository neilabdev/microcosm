module Microcosm
  class Util
    def self.models(*args)
      params = args[-1].is_a?(Hash) ? args[-1] : {}
      options = {
          table_names: false
      }.merge(params)

      Rails.application.eager_load!

      children = {}
      make_mapping = lambda { |klazz|
        {
            belongs_to: klazz.send(:reflect_on_all_associations, :belongs_to).collect { |r| #child
              next nil if r.options[:polymorphic]
              #klass = r.klass unless r.options[:polymorphic]
              (children[r.klass.name] ||= []).push(klazz)
              r.klass
            }.select { |k| k.present? },
            has_many: klazz.send(:reflect_on_all_associations, :has_many).collect { |r|
              r.klass unless r.options[:polymorphic]
            }.select { |k| k.present? },
            type: klazz,
            children: (children[klazz.name] ||= [])
        }
      }

      unsorted_descendants = ApplicationRecord.descendants
      mappings = Hash[unsorted_descendants.collect { |d| [d.name, make_mapping.call(d)] }]
      resolved_dependencies = []
      deep_resolve = lambda { |klazzees, resolved|
        for klazz in klazzees do
          for parent in mappings[klazz.name][:belongs_to]
            deep_resolve.call([parent], resolved) unless resolved.include?(parent)
          end
          resolved.push(klazz) unless resolved.include?(klazz)
        end
        resolved
      }

      resolved_descendants = deep_resolve.call(unsorted_descendants, resolved_dependencies)

      options[:table_names] ?
          resolved_descendants.collect { |t| t.table_name } :
          resolved_descendants
    end
  end
end