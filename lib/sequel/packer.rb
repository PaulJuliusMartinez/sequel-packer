require 'sequel'

module Sequel
  class Packer
    # For invalid arguments provided to the field class method.
    class FieldArgumentError < ArgumentError; end
    # Must declare a model with `model MyModel` before calling field.
    class ModelNotYetDeclaredError < StandardError; end
    class AssociationDoesNotExistError < StandardError; end
    class InvalidAssociationPackerError < StandardError; end
    class UnknownTraitError < StandardError; end
    class UnnecessaryWithContextError < StandardError; end

    def self.inherited(subclass)
      subclass.instance_variable_set(:@model, @model)
      subclass.instance_variable_set(:@class_fields, @class_fields&.dup || [])
      subclass.instance_variable_set(:@class_traits, @class_traits&.dup || {})
      subclass.instance_variable_set(:@class_packers, @class_packers&.dup || {})
      subclass.instance_variable_set(
        :@class_eager_hash,
        EagerHash.deep_dup(@class_eager_hash),
      )
      subclass.instance_variable_set(
        :@class_precomputations,
        @class_precomputations&.dup || [],
      )
      subclass.instance_variable_set(
        :@class_with_contexts,
        @class_with_contexts&.dup || [],
      )
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
      Validation.check_field_arguments(
        @model, field_name, packer_class, traits, &block)
      field_type = determine_field_type(field_name, packer_class, block)

      if field_type == ASSOCIATION_FIELD
        set_association_packer(field_name, packer_class, *traits)
      end

      @class_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    def self.set_association_packer(association, packer_class, *traits)
      Validation.check_association_packer(
        @model, association, packer_class, traits)
      @class_packers[association] = [packer_class, traits]
    end

    private_class_method def self.determine_field_type(
      field_name,
      packer_class,
      block
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

    def self.precompute(&block)
      if !block
        raise ArgumentError, 'Sequel::Packer.precompute must be passed a block'
      end
      @class_precomputations << block
    end

    def self.with_context(&block)
      if !block
        raise ArgumentError, 'Sequel::Packer.with_context must be passed a block'
      end
      @class_with_contexts << block
    end

    def initialize(*traits, **context)
      @context = context

      @subpackers = nil

      # Technically we only need to duplicate these fields if we modify any of
      # them, but manually implementing some sort of copy-on-write functionality
      # is messy and error prone.
      @instance_fields = class_fields.dup
      @instance_packers = class_packers.dup
      @instance_eager_hash = EagerHash.deep_dup(class_eager_hash)
      @instance_precomputations = class_precomputations.dup

      class_with_contexts.each do |with_context_block|
        self.instance_exec(&with_context_block)
      end

      # Evaluate trait blocks, which might add new fields to @instance_fields,
      # new packers to @instance_packers, new associations to
      # @instance_eager_hash, and/or new precomputations to
      # @instance_precomputations.
      traits.each do |trait|
        trait_block = class_traits[trait]
        if !trait_block
          raise UnknownTraitError, "Unknown trait for #{self.class}: :#{trait}"
        end

        self.instance_exec(&trait_block)
      end

      # Create all the subpackers, and merge in their eager hashes.
      @instance_packers.each do |association, (packer_class, traits)|
        association_packer = packer_class.new(*traits, @context)

        @subpackers ||= {}
        @subpackers[association] = association_packer

        @instance_eager_hash = EagerHash.merge!(
          @instance_eager_hash,
          {association => association_packer.send(:eager_hash)},
        )
      end
    end

    def pack(to_be_packed)
      case to_be_packed
      when Sequel::Dataset
        if @instance_eager_hash
          to_be_packed = to_be_packed.eager(@instance_eager_hash)
        end
        models = to_be_packed.all

        run_precomputations(models)
        pack_models(models)
      when Sequel::Model
        if @instance_eager_hash
          EagerLoading.eager_load(
            class_model,
            [to_be_packed],
            @instance_eager_hash
          )
        end

        run_precomputations([to_be_packed])
        pack_model(to_be_packed)
      when Array
        if @instance_eager_hash
          EagerLoading.eager_load(
            class_model,
            to_be_packed,
            @instance_eager_hash
          )
        end

        run_precomputations(to_be_packed)
        pack_models(to_be_packed)
      when NilClass
        nil
      end
    end

    private

    def run_precomputations(models)
      @instance_packers.each do |association, _|
        subpacker = @subpackers[association]
        next if !subpacker.send(:has_precomputations?)

        reflection = class_model.association_reflection(association)

        if reflection.returns_array?
          all_associated_records = models.flat_map {|m| m.send(association)}.uniq
        else
          all_associated_records = models.map {|m| m.send(association)}.compact
        end

        subpacker.send(:run_precomputations, all_associated_records)
      end

      @instance_precomputations.each do |block|
        instance_exec(models, &block)
      end
    end

    def has_precomputations?
      return true if @instance_precomputations.any?
      return false if !@subpackers
      @subpackers.values.any? {|sp| sp.send(:has_precomputations?)}
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
        packer.send(:pack_models, associated_models)
      else
        packer.send(:pack_model, associated_models)
      end
    end

    def field(field_name=nil, packer_class=nil, *traits, &block)
      klass = self.class

      Validation.check_field_arguments(
        class_model, field_name, packer_class, traits, &block)
      field_type =
        klass.send(:determine_field_type, field_name, packer_class, block)

      if field_type == ASSOCIATION_FIELD
        set_association_packer(field_name, packer_class, *traits)
      end

      @instance_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    def set_association_packer(association, packer_class, *traits)
      Validation.check_association_packer(
        class_model, association, packer_class, traits)

      @instance_packers[association] = [packer_class, traits]
    end

    def eager(*associations)
      @instance_eager_hash = EagerHash.merge!(
        @instance_eager_hash,
        EagerHash.normalize_eager_args(*associations),
      )
    end

    def precompute(&block)
      if !block
        raise ArgumentError, 'Sequel::Packer.precompute must be passed a block'
      end
      @instance_precomputations << block
    end

    def with_context(&block)
      raise(
        UnnecessaryWithContextError,
        'There is no need to call with_context from within a trait block; ' +
          '@context can be accessed directly.',
      )
    end

    def eager_hash
      @instance_eager_hash
    end

    def class_model
      self.class.instance_variable_get(:@model)
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

    def class_precomputations
      self.class.instance_variable_get(:@class_precomputations)
    end

    def class_with_contexts
      self.class.instance_variable_get(:@class_with_contexts)
    end
  end
end

require 'sequel/packer/eager_hash'
require 'sequel/packer/eager_loading'
require 'sequel/packer/validation'
require "sequel/packer/version"
