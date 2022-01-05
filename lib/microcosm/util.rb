module Microcosm
  class Util
    def self.models(*args)
      params = args[-1].is_a?(Hash) ? args[-1] : {}
      options = {
        table_names: false
      }.merge(params)

      Rails.application.eager_load!
      class_cache = ActiveRecord::Base.descendants.collect {|c| [c.name,c]}.to_h
      children_of = {} #children_of
      parents_of = {} #parents_of
      make_mapping = lambda { |klazz|
        {
          belongs_to: klazz.send(:reflect_on_all_associations, :belongs_to).collect { |r| #child
            next nil if r.options[:polymorphic] #|| r.options[:through]
            next nil if r.class_name == klazz.name
            begin
              (children_of[r.class_name] ||= []).push(klazz)
              (parents_of[klazz.name] ||= []).push(r.class_name.constantize)

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
          children: (children_of[klazz.name] ||= []),
          parents:  (parents_of[klazz.name] ||= []),
        }
      }

      unsorted_descendants = ActiveRecord::Base.descendants - [ApplicationRecord]
      mappings = Hash[unsorted_descendants.collect { |d| [d.name, make_mapping.call(d)] }   ]
      resolved_dependencies = []
      stacked_dependencies = []
      deep_resolve = lambda { |klazzees, resolved, stacked|
        resolved ||= []
        for klazz in Array.wrap(klazzees).flatten do
          klazz_parents = (mappings.dig(klazz.name,:belongs_to) || []).flatten.uniq - [klazz]
          for parent in klazz_parents
            is_resolved =  resolved.include?(parent) || stacked.include?(parent)
            unless is_resolved then
              stacked.push(parent)
              deep_resolve.call(parent, resolved,stacked)
              stacked.pop
            end
          end # for parent
          resolved.push(klazz) unless resolved.include?(klazz)
        end # for klazz
        resolved
      }

      loop do
        unsorted_class = unsorted_descendants.pop

        deep_resolved = deep_resolve.call(unsorted_class, nil,stacked_dependencies)

        resolved_dependencies.append deep_resolved

        break if  unsorted_descendants.blank?
      end

      sorted_dependencies = resolved_dependencies.sort_by { |a| a.size }.reverse.flatten.uniq
      options[:table_names] ?
        sorted_dependencies.collect { |t| t.table_name } :
        sorted_dependencies
    end
  end
end