module Sequel
  class Packer
    module EagerHash
      # An eager hash cannot have the form: {
      #   :assoc1 => :nested_assoc,
      #   <proc> => :assoc2,
      # }
      class MixedProcHashError < StandardError; end
      # An eager hash cannot have multiple keys that are Procs.
      class MultipleProcKeysError < StandardError; end
      # If an eager hash contains a Proc as the key of a hash, that value at
      # that key cannot be another hash with a Proc as a key.
      class NestedEagerProcsError < StandardError; end

      # Sequel's eager function can accept arguments in a number of different
      # formats:
      #   .eager(:assoc)
      #   .eager([:assoc1, :assoc2])
      #   .eager(assoc: :nested_assoc)
      #   .eager(
      #     :assoc1,
      #     assoc2: {(proc {|ds| ...}) => [:nested_assoc1, :nested_assoc2]},
      #   )
      #
      # This method normalizes these arguments such that:
      # - A Hash is returned
      # - The keys of that hash are the names of associations
      # - The values of that hash are either:
      #   - nil, representing no nested associations
      #   - a nested normalized hash, meeting these definitions
      #   - a "Proc hash", which is a hash with a single key, which is a proc,
      #     and whose value is either nil or a nested normalized hash.
      #
      # Notice that a normalized has the property that every value in the hash
      # is either nil, or itself a normalized hash.
      #
      # Note that this method cannot return a "Proc hash" as the top level
      # normalized hash; Proc hashes can only be nested under other
      # associations.
      def self.normalize_eager_args(*associations)
        # Implementation largely borrowed from Sequel's
        # eager_options_for_associations:
        #
        # https://github.com/jeremyevans/sequel/blob/5.32.0/lib/sequel/model/associations.rb#L3228-L3245
        normalized_hash = {}

        associations.flatten.each do |association|
          case association
          when Symbol
            normalized_hash[association] = nil
          when Hash
            num_proc_keys = 0
            num_symbol_keys = 0

            association.each do |key, val|
              case key
              when Symbol
                num_symbol_keys += 1
              when Proc
                num_proc_keys += 1

                if val.is_a?(Proc) || is_proc_hash?(val)
                  raise(
                    NestedEagerProcsError,
                    "eager hash has nested Procs: #{associations.inspect}",
                  )
                end
              end

              if val.nil?
                # Already normalized
                normalized_hash[key] = nil
              elsif val.is_a?(Proc)
                # Convert Proc value to a Proc hash.
                normalized_hash[key] = {val => nil}
              else
                # Otherwise recurse.
                normalized_hash[key] = normalize_eager_args(val)
              end
            end

            if num_proc_keys > 1
              raise(
                MultipleProcKeysError,
                "eager hash has multiple Proc keys: #{associations.inspect}",
              )
            end

            if num_proc_keys > 0 && num_symbol_keys > 0
              raise(
                MixedProcHashError,
                'eager hash has both symbol keys and Proc keys: ' +
                  associations.inspect,
              )
            end
          else
            raise(
              Sequel::Error,
              'Associations must be in the form of a symbol or hash',
            )
          end
        end

        normalized_hash
      end

      def self.is_proc_hash?(hash)
        return false if !hash.is_a?(Hash)
        return false if hash.size != 1
        hash.keys[0].is_a?(Proc)
      end

      # Merges two eager hashes together, without modifying either one.
      def self.merge(hash1, hash2)
        return deep_dup(hash2) if !hash1
        merge!(deep_dup(hash1), hash2)
      end

      # Merges two eager hashes together, modifying the first hash, while
      # leaving the second unmodified. Since the first argument may be nil,
      # callers should still use the return value, rather than the first
      # argument.
      def self.merge!(hash1, hash2)
        return hash1 if !hash2
        return deep_dup(hash2) if !hash1

        hash2.each do |key, val2|
          if !hash1.key?(key)
            hash1[key] = deep_dup(val2)
            next
          end

          val1 = hash1[key]
          h1_is_proc_hash = is_proc_hash?(val1)
          h2_is_proc_hash = is_proc_hash?(val2)

          case [h1_is_proc_hash, h2_is_proc_hash]
          when [false, false]
            hash1[key] = merge!(val1, val2)
          when [true, false]
            # We want to actually merge the hash the proc points to.
            eager_proc, nested_hash = val1.entries[0]
            hash1[key] = {eager_proc => merge!(nested_hash, val2)}
          when [false, true]
            # Same as above, but flipped. Notice the order of the arguments to
            # merge! to ensure hash2 is not modified!
            eager_proc, nested_hash = val2.entries[0]
            hash1[key] = {eager_proc => merge!(val1, nested_hash)}
          when [true, true]
            # Create a new proc that applies both procs, then merge their
            # respective hashes.
            proc1, nested_hash1 = val1.entries[0]
            proc2, nested_hash2 = val2.entries[0]

            new_proc = (proc {|ds| proc2.call(proc1.call(ds))})

            hash1[key] = {new_proc => merge!(nested_hash1, nested_hash2)}
          end
        end

        hash1
      end

      # Creates a deep copy of an eager hash.
      def self.deep_dup(hash)
        return nil if !hash
        hash.transform_values {|val| deep_dup(val)}
      end
    end
  end
end
