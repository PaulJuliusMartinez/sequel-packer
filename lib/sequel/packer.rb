module Sequel
  class Packer
    # For invalid arguments provided to the field class method.
    class FieldArgumentError < ArgumentError; end

    def self.inherited(subclass)
      subclass.instance_variable_set(:@fields, [])
    end

    def self.field(field_name=nil, &block)
      if block
        arity = block.arity

        if field_name && (arity != 1 && arity != -1)
          raise(
            FieldArgumentError,
            "The block used to define :#{field_name} must accept exactly " +
              'one argument.',
          )
        end

        if !field_name && arity != 2
          raise(
            FieldArgumentError,
            'When passing an arbitrary block to Sequel::Packer::field, the ' +
              'block must accept exactly two arguments: the model and the ' +
              'partially packed hash.',
          )
        end
      end

      @fields << {
        name: field_name,
        block: block,
      }
    end

    def fields
      self.class.instance_variable_get(:@fields)
    end

    def pack(dataset)
      dataset.map do |model|
        h = {}

        fields.each do |field_options|
          field_name = field_options[:name]
          block = field_options[:block]

          if block
            if field_name
              h[field_name] = block.call(model)
            else
              block.call(model, h)
            end
          else
            h[field_name] = model.send(field_name)
          end
        end

        h
      end
    end
  end
end

require "sequel/packer/version"
