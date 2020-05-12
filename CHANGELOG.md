### 0.1.0 (2020-05-11)

* Add traits.

### 0.0.2 (2020-05-11)

* Add support for `Sequel::Packer.field(key, &block)` and
  `Sequel::Packer.field(&block)`
* Add validation to `Sequel::Packer::field` to detect incorrect usage.
* Add support for nested packing of associations using
  `Sequel::Packer.field(association, packer_class)`
* Update README with usage instructions and basic API reference.

### 0.0.1 (2020-05-10)

* Most basic functionality for serializing single fields
