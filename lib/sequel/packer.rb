module Sequel
  class Packer
    def self.inherited(subclass)
      subclass.instance_variable_set(:@fields, [])
    end

    def self.field(field_name)
      @fields << field_name
    end

    def fields
      self.class.instance_variable_get(:@fields)
    end

    def pack(dataset)
      dataset.map do |model|
        h = {}
        fields.each do |field_name|
          h[field_name] = model.send(field_name)
        end
        h
      end
    end
  end
end

require "sequel/packer/version"
