module Sequel
  class Packer
    # For invalid arguments provided to the field class method.
    class FieldArgumentError < ArgumentError; end
    # Must declare a model with `model MyModel` before calling field.
    class ModelNotYetDeclaredError < StandardError; end

    def self.inherited(subclass)
      subclass.instance_variable_set(:@class_fields, [])
      subclass.instance_variable_set(:@class_traits, {})
      subclass.instance_variable_set(:@class_packers, {})
      subclass.instance_variable_set(:@class_eager_hash, nil)
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

    # field(:foo)
    METHOD_FIELD = :method_field
    # field(:foo, &block)
    BLOCK_FIELD = :block_field
    # field(:association, packer_class)
    ASSOCIATION_FIELD = :association_field
    # field(&block)
    ARBITRARY_MODIFICATION_FIELD = :arbitrary_modification_field

    def self.field(field_name=nil, packer_class=nil, *traits, &block)
      validate_field_args(field_name, packer_class, *traits, &block)
      field_type = determine_field_type(field_name, packer_class, &block)

      if field_type == ASSOCIATION_FIELD
        @class_packers[field_name] = [packer_class, traits]
      end

      @class_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    def self.set_association_packer(association, packer_class, *traits)
      @class_packers[association] = [packer_class, traits]
    end

    private_class_method def self.determine_field_type(
      field_name=nil,
      packer_class=nil,
      &block
    )
      if block
        if field_name
          BLOCK_FIELD
        else
          ARBITRARY_MODIFICATION_FIELD
        end
      else
        if packer_class
          ASSOCIATION_FIELD
        else
          METHOD_FIELD
        end
      end
    end

    private_class_method def self.validate_field_args(
      field_name=nil,
      packer_class=nil,
      *traits,
      &block
    )
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
        if packer_class || traits.any?
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

        # When using Symbol.to_proc (field(:foo, &:calculate_foo)), the block has arity -1.
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

        if packer_class || traits.any?
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

          if !(association_model <= packer_class_model)
            raise(
              FieldArgumentError,
              "Model for association packer (#{packer_class_model}) " +
                "doesn't match model for the #{field_name} association " +
                "(#{association_model})",
            )
          end

          packer_class_traits = packer_class.instance_variable_get(:@class_traits)
          traits.each do |trait|
            if !packer_class_traits.key?(trait)
              raise(
                FieldArgumentError,
                "Trait :#{trait} isn't defined for #{packer_class} used to " +
                  "pack #{field_name} association.",
              )
            end
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
    end

    def self.trait(name, &block)
      if @class_traits.key?(name)
        raise ArgumentError, "Trait :#{name} already defined"
      end
      if !block_given?
        raise ArgumentError, 'Must give a block when defining a trait'
      end
      @class_traits[name] = block
    end

    def self.eager(*associations)
      @class_eager_hash = EagerHash.merge!(
        @class_eager_hash,
        EagerHash.normalize_eager_args(*associations),
      )
    end

    def initialize(*traits)
      @subpackers = nil

      # If there aren't any traits, we can just re-use the class variables.
      if traits.empty?
        @instance_fields = class_fields
        @instance_packers = class_packers
        @instance_eager_hash = class_eager_hash
      else
        @instance_fields = class_fields.dup
        @instance_packers = class_packers.dup
        @instance_eager_hash = EagerHash.deep_dup(class_eager_hash)
      end

      # Evaluate trait blocks, which might add new fields to @instance_fields,
      # new packers to @instance_packers, and/or new associations to
      # @instance_eager_hash.
      traits.each do |trait|
        trait_block = class_traits[trait]
        if !trait_block
          raise ArgumentError, "Unknown trait for #{self.class}: :#{trait}"
        end

        self.instance_exec(&trait_block)
      end

      # Create all the subpackers, and merge in their eager hashes.
      @instance_packers.each do |association, (packer_class, traits)|
        association_packer = packer_class.new(*traits)

        @subpackers ||= {}
        @subpackers[association] = association_packer

        @instance_eager_hash = EagerHash.merge!(
          @instance_eager_hash,
          {association => association_packer.send(:eager_hash)},
        )
      end
    end

    def pack(dataset)
      dataset = dataset.eager(@instance_eager_hash) if @instance_eager_hash
      models = dataset.all
      pack_models(models)
    end

    def pack_model(model)
      h = {}

      @instance_fields.each do |field_options|
        field_name = field_options[:name]

        case field_options[:type]
        when METHOD_FIELD
          h[field_name] = model.send(field_name)
        when BLOCK_FIELD
          h[field_name] = instance_exec(model, &field_options[:block])
        when ASSOCIATION_FIELD
          associated_objects = model.send(field_name)
          h[field_name] = pack_association(field_name, associated_objects)
        when ARBITRARY_MODIFICATION_FIELD
          instance_exec(model, h, &field_options[:block])
        end
      end

      h
    end

    def pack_models(models)
      models.map {|m| pack_model(m)}
    end

    def pack_association(association, associated_models)
      return nil if !associated_models

      packer = @subpackers[association]

      if associated_models.is_a?(Array)
        packer.pack_models(associated_models)
      else
        packer.pack_model(associated_models)
      end
    end

    private

    def field(field_name=nil, packer_class=nil, *traits, &block)
      klass = self.class
      klass.send(
        :validate_field_args, field_name, packer_class, *traits, &block)
      field_type =
        klass.send(:determine_field_type, field_name, packer_class, &block)

      if field_type == ASSOCIATION_FIELD
        @instance_packers[field_name] = [packer_class, traits]
      end

      @instance_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    def set_association_packer(association, packer_class, *traits)
      @instance_packers[association] = [packer_class, traits]
    end

    def eager_hash
      @instance_eager_hash
    end

    def eager(*associations)
      @instance_eager_hash = EagerHash.merge!(
        @instance_eager_hash,
        EagerHash.normalize_eager_args(*associations),
      )
    end

    def class_fields
      self.class.instance_variable_get(:@class_fields)
    end

    def class_eager_hash
      self.class.instance_variable_get(:@class_eager_hash)
    end

    def class_packers
      self.class.instance_variable_get(:@class_packers)
    end

    def class_traits
      self.class.instance_variable_get(:@class_traits)
    end
  end
end

require 'sequel/packer/eager_hash'
require "sequel/packer/version"
