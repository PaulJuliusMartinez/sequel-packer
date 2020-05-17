module Sequel
  class Packer
    module EagerLoading
      # This methods allows eager loading associations _after_ a record, or
      # multiple records, have been fetched from the database. It is useful when
      # you know you will be accessing model associations, but models have
      # already been materialized.
      #
      # This method accepts a normalized_eager_hash, as specified by
      # Sequel::Packer::EagerHash.
      #
      # This method will handle procs used to filter association datasets, but
      # if an association has already been loaded for every model, the dataset
      # will not be refetched and the proc will not be applied.
      #
      # This method borrows a lot from the #eager_load Sequel::Dataset method
      # defined in Sequels lib/sequel/model/associations.rb.
      def self.eager_load(model_class, model_or_models, normalized_eager_hash)
        models = model_or_models.is_a?(Array) ?
          model_or_models :
          [model_or_models]

        # Cache to avoid building id maps multiple times.
        key_hash = {}

        normalized_eager_hash.each do |association, nested_associations|
          eager_block = nil

          if EagerHash.is_proc_hash?(nested_associations)
            eager_block, nested_associations = nested_associations.entries[0]
          end

          reflection = model_class.association_reflections[association]

          # If all of the models have already loaded the association, we'll just
          # recursively call ::eager_load to load nested associations.
          if models.all? {|m| m.associations.key?(association)}
            if nested_associations
              associated_records = if reflection.returns_array?
                models.flat_map {|m| m.send(association)}.uniq
              else
                models.map {|m| m.send(association)}.compact
              end

              eager_load(
                reflection.associated_class,
                associated_records,
                nested_associations,
              )
            end
          else
            key = reflection.eager_loader_key
            id_map = nil

            if key && !key_hash[key]
              id_map = Hash.new {|h, k| h[k] = []}

              models.each do |model|
                case key
                when Symbol
                  model_id = model.get_column_value(key)
                  id_map[model_id] << model if model_id
                when Array
                  model_id = key.map {|col| model.get_column_value(col)}
                  id_map[model_id] << model if model_id.all?
                else
                  raise(
                    Sequel::Error,
                    "unhandled eager_loader_key #{key.inspect} for " +
                      "association #{association}",
                  )
                end
              end
            end

            loader = reflection[:eager_loader]

            loader.call(
              key_hash: key_hash,
              rows: models,
              associations: nested_associations,
              self: self,
              eager_block: eager_block,
              id_map: id_map,
            )

            if reflection[:after_load]
              models.each do |model|
                model.send(
                  :run_association_callbacks,
                  reflection,
                  :after_load,
                  model.associations[association],
                )
              end
            end
          end
        end
      end
    end
  end
end
