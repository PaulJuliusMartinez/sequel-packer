module Sequel
  class Packer
    # For invalid arguments provided to the field class method.
    class FieldArgumentError < ArgumentError; end
    # Must declare a model with `model MyModel` before calling field.
    class ModelNotYetDeclaredError < StandardError; end

    def self.inherited(subclass)
      subclass.instance_variable_set(:@fields, [])
    end

    def self.model(klass)
      if !(klass < Sequel::Model)
        fail(
          ArgumentError,
          'model declaration must be a subclass of Sequel::Model',
        )
      end

      fail ArgumentError, 'model already declared' if @model

      @model = klass
    end

    def self.field(field_name=nil, packer_class=nil, &block)
      fail ModelNotYetDeclaredError if !@model

      # This check applies to all invocations:
      if field_name && !field_name.is_a?(Symbol) && !field_name.is_a?(String)
        raise(
          FieldArgumentError,
          'Field name passed to Sequel::Packer::field must be a Symbol or ' +
            'a String.',
        )
      end

      if block
        # If the user passed a block, we'll assume they either want:
        #     field :foo {|model| ...}
        # or  field {|model, hash| ...}
        #
        if packer_class
          raise(
            FieldArgumentError,
            'When passing a block to Sequel::Packer::field, either pass the ' +
              'name of field as a single argument (e.g., field(:foo) ' +
              '{|model| ...}), or nothing at all to perform arbitrary ' +
              'modifications of the final hash (e.g., field {|model, hash| ' +
              '...}).',
          )
        end

        arity = block.arity

        if field_name && arity != 1 && arity != -1
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
      else
        # In this part of the if, block is not defined

        if !field_name
          # Note that this error isn't technically true, but usage of the
          # field {|model, hash| ...} variant is likely pretty rare.
          raise(
            FieldArgumentError,
            'Must pass a field name to Sequel::Packer::field.',
          )
        end

        if packer_class
          if !@model.associations.include?(field_name)
            raise(
              FieldArgumentError,
              'Passing multiple arguments to Sequel::Packer::field ' +
                'is used to serialize associations with designated ' +
                "packers, but the association #{field_name} does not " +
                "exist on #{@model}.",
            )
          end

          if !(packer_class < Sequel::Packer)
            raise(
              FieldArgumentError,
              'When declaring the serialization behavior for an ' +
                'association, the second argument must be a Sequel::Packer ' +
                "subclass. #{packer_class} is not a subclass of " +
                'Sequel::Packer.',
            )
          end

          association_model =
            @model.association_reflections[field_name].associated_class
          packer_class_model = packer_class.instance_variable_get(:@model)

          if !(association_model < packer_class_model)
            raise(
              FieldArgumentError,
              "Model for association packer (#{packer_class_model}) " +
                "doesn't match model for the #{field_name} association " +
                "(#{association_model})",
            )
          end
        else
          if @model.associations.include?(field_name)
            raise(
              FieldArgumentError,
              'When declaring a field for a model association, you must ' +
                'also pass a Sequel::Packer class to use as the second ' +
                'argument to field.',
            )
          end
        end
      end

      @fields << {
        name: field_name,
        block: block,
      }
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

    private

    def fields
      self.class.instance_variable_get(:@fields)
    end
  end
end

require "sequel/packer/version"
