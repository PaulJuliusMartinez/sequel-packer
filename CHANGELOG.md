### 0.3.0 (2020-05-14)

* Add `self.set_association_packer(association, packer_class, *traits)` and
  `self.pack_association(association, models)` for more flexible packing of
  associations.
* Improve internal code quality.

### 0.2.0 (2020-05-13)

* Add support for `Sequel::Packer.eager(*associations)`
* Use `Sequel::Dataset.eager` in the background when fetching a dataset to avoid
  N+1 query issues.

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
