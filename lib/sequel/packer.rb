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

    # Think of this method as the "initialize" method for a Packer class.
    # Every Packer class keeps track of the fields, traits, and other various
    # operations defined using the DSL internally.
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

    # Declare the type of Sequel::Model this Packer will be used for. Used to
    # validate associations at declaration time.
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
    # field(:association, subpacker)
    ASSOCIATION_FIELD = :association_field
    # field(&block)
    ARBITRARY_MODIFICATION_FIELD = :arbitrary_modification_field

    # Declare a field to be packed in the output hash. This method can be called
    # in multiple ways:
    #
    # field(:field_name)
    # - Calls the method :field_name on a model and stores the result under the
    #   key :field_name in the packed hash.
    #
    # field(:field_name, &block)
    # - Yields the model to the block and stores the result under the key
    #   :field_name in the packed hash.
    #
    # field(:association, subpacker, *traits)
    # - Packs model.association using the designated subpacker with the
    #   specified traits.
    #
    # field(&block)
    # - Yields the model and the partially packed hash to the block, allowing
    #   for arbitrary modification of the output hash.
    def self.field(field_name=nil, subpacker=nil, *traits, &block)
      Validation.check_field_arguments(
        @model, field_name, subpacker, traits, &block)
      field_type = determine_field_type(field_name, subpacker, block)

      if field_type == ASSOCIATION_FIELD
        set_association_packer(field_name, subpacker, *traits)
      end

      @class_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    # Helper for determing a field type from the arguments to field.
    private_class_method def self.determine_field_type(
      field_name,
      subpacker,
      block
    )
      if block
        if field_name
          BLOCK_FIELD
        else
          ARBITRARY_MODIFICATION_FIELD
        end
      else
        if subpacker
          ASSOCIATION_FIELD
        else
          METHOD_FIELD
        end
      end
    end

    # Register that nested models related to the packed model by association
    # should be packed using the given subpacker with the specified traits.
    def self.set_association_packer(association, subpacker, *traits)
      Validation.check_association_packer(
        @model, association, subpacker, traits)
      @class_packers[association] = [subpacker, traits]
    end

    # Define a trait, a set of optional fields that can be packed in certain
    # situations. The block can call main Packer DSL methods: field,
    # set_association_packer, eager, or precompute.
    def self.trait(name, &block)
      if @class_traits.key?(name)
        raise ArgumentError, "Trait :#{name} already defined"
      end
      if !block_given?
        raise ArgumentError, 'Must give a block when defining a trait'
      end
      @class_traits[name] = block
    end

    # Specify additional eager loading that should take place when fetching data
    # to be packed. Commonly used to add filters to association datasets via
    # eager procs.
    #
    # Users should not assume when using eager procs that the proc actually gets
    # executed. If models with their associations already loaded are passed to
    # pack then the proc will never get processed. Any filtering logic should be
    # duplicated within a field block.
    def self.eager(*associations)
      @class_eager_hash = EagerHash.merge!(
        @class_eager_hash,
        EagerHash.normalize_eager_args(*associations),
      )
    end

    # Declare an arbitrary operation to be performed one all the data has been
    # fetched. The block will be executed once and be passed all of the models
    # that will be packed by this Packer, even if this Packer is nested as a
    # subpacker of other packers. The block can save the result of the
    # computation in an instance variable which can then be accessed in the
    # blocks passed to field.
    def self.precompute(&block)
      if !block
        raise ArgumentError, 'Sequel::Packer.precompute must be passed a block'
      end
      @class_precomputations << block
    end

    # Declare a block to be called after a Packer has been initialized with
    # context. The block can call the common Packer DSL methods. It is most
    # commonly used to pass eager procs that depend on the Packer context to
    # eager.
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
      @instance_packers.each do |association, (subpacker, traits)|
        association_packer = subpacker.new(*traits, @context)

        @subpackers ||= {}
        @subpackers[association] = association_packer

        @instance_eager_hash = EagerHash.merge!(
          @instance_eager_hash,
          {association => association_packer.send(:eager_hash)},
        )
      end
    end

    # Pack the given data with the traits and additional context specified when
    # the Packer instance was created.
    #
    # Data can be provided as a Sequel::Dataset, an array of Sequel::Models, a
    # single Sequel::Model, or nil. Even when passing models that have already
    # been materialized, eager loading will be used to efficiently fetch
    # associations.
    #
    # Returns an array of packed hashes, or a single packed hash if a single
    # model was passed in. Returns nil if nil was passed in.
    def pack(data)
      case data
      when Sequel::Dataset
        data = data.eager(@instance_eager_hash) if @instance_eager_hash
        models = data.all

        run_precomputations(models)
        pack_models(models)
      when Sequel::Model
        if @instance_eager_hash
          EagerLoading.eager_load(class_model, [data], @instance_eager_hash)
        end

        run_precomputations([data])
        pack_model(data)
      when Array
        if @instance_eager_hash
          EagerLoading.eager_load(class_model, data, @instance_eager_hash)
        end

        run_precomputations(data)
        pack_models(data)
      when NilClass
        nil
      end
    end

    private

    # Run any blocks declared using precompute on the given models, as well as
    # any precompute blocks declared by subpackers.
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

    # Check if a Packer has any precompute blocks declared, to avoid the
    # overhead of flattening the child associations.
    def has_precomputations?
      return true if @instance_precomputations.any?
      return false if !@subpackers
      @subpackers.values.any? {|sp| sp.send(:has_precomputations?)}
    end

    # Pack a single model by processing all of the Packer's declared fields.
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

    # Pack an array of models by processing all of the Packer's declared fields.
    def pack_models(models)
      models.map {|m| pack_model(m)}
    end

    # Pack models from an association using the designated subpacker.
    def pack_association(association, associated_models)
      return nil if !associated_models

      packer = @subpackers[association]

      if associated_models.is_a?(Array)
        packer.send(:pack_models, associated_models)
      else
        packer.send(:pack_model, associated_models)
      end
    end

    # See the definition of self.field. This method accepts the exact same
    # arguments. When fields are declared within trait blocks, this method is
    # called rather than the class method.
    def field(field_name=nil, subpacker=nil, *traits, &block)
      klass = self.class

      Validation.check_field_arguments(
        class_model, field_name, subpacker, traits, &block)
      field_type =
        klass.send(:determine_field_type, field_name, subpacker, block)

      if field_type == ASSOCIATION_FIELD
        set_association_packer(field_name, subpacker, *traits)
      end

      @instance_fields << {
        type: field_type,
        name: field_name,
        block: block,
      }
    end

    # See the definition of self.set_association_packer. This method accepts the
    # exact same arguments. When used within a trait block, this method is
    # called rather than the class method.
    def set_association_packer(association, subpacker, *traits)
      Validation.check_association_packer(
        class_model, association, subpacker, traits)

      @instance_packers[association] = [subpacker, traits]
    end

    # See the definition of self.eager. This method accepts the exact same
    # arguments. When used within a trait block, this method is called rather
    # than the class method.
    def eager(*associations)
      @instance_eager_hash = EagerHash.merge!(
        @instance_eager_hash,
        EagerHash.normalize_eager_args(*associations),
      )
    end

    # See the definition of self.precompute. This method accepts the exact same
    # arguments. When used within a trait block, this method is called rather
    # than the class method.
    def precompute(&block)
      if !block
        raise ArgumentError, 'Sequel::Packer.precompute must be passed a block'
      end
      @instance_precomputations << block
    end

    # See the definition of self.with_context. This method accepts the exact
    # same arguments. When used within a trait block, this method is called
    # rather than the class method.
    def with_context(&block)
      raise(
        UnnecessaryWithContextError,
        'There is no need to call with_context from within a trait block; ' +
          '@context can be accessed directly.',
      )
    end

    # Access the internal eager hash.
    def eager_hash
      @instance_eager_hash
    end

    # The following methods expose the class instance variables containing the
    # core definition of the Packer.

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
