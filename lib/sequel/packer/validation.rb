require 'sequel'

module Sequel
  class Packer
    module Validation
      # Cheks for common errors when using the field method. Additional
      # checks around the packer class and traits occur in
      # check_association_packer.
      def self.check_field_arguments(
        model,
        field_name,
        packer_class,
        traits,
        &block
      )
        fail ModelNotYetDeclaredError if !model

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

          if model.associations.include?(field_name) && !packer_class
            raise(
              InvalidAssociationPackerError,
              "#{field_name} is an association of #{model}. You must also " +
                'pass a Sequel::Packer class to be used when serializing ' +
                'this association.',
            )
          end
        end
      end

      # Performs various checks when using
      #   field(association, packer_class, *traits)
      #   or
      #   set_association_packer(association, packer_class, *traits)
      def self.check_association_packer(
        model,
        association,
        packer_class,
        traits
      )
        if !model.associations.include?(association)
          raise(
            AssociationDoesNotExistError,
            "The association :#{association} does not exist on #{model}.",
          )
        end

        if !packer_class || !(packer_class < Sequel::Packer)
          raise(
            InvalidAssociationPackerError,
            'You must pass a Sequel::Packer class to use when packing the ' +
              ":#{association} association. #{packer_class} is not a " +
              "subclass of Sequel::Packer."
          )
        end

        association_model =
          model.association_reflections[association].associated_class
        packer_class_model = packer_class.instance_variable_get(:@model)

        if !(association_model <= packer_class_model)
          raise(
            InvalidAssociationPackerError,
            "Model for association packer (#{packer_class_model}) " +
              "doesn't match model for the #{association} association " +
              "(#{association_model})",
          )
        end

        packer_class_traits = packer_class.instance_variable_get(:@class_traits)
        traits.each do |trait|
          if !packer_class_traits.key?(trait)
            raise(
              UnknownTraitError,
              "Trait :#{trait} isn't defined for #{packer_class} used to " +
                "pack #{association} association.",
            )
          end
        end
      end
    end
  end
end
