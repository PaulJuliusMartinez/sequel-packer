### 1.0.2 (2023-05-11)

* Update validation of the arity of the blocks passed to `field` to account
  for the change in the arity of procs created by `&:sym` in Ruby 3. The updated
  validation should support both Ruby 2 and Ruby 3 versions.

### 1.0.1 (2021-08-02)

* Update internal method call to remove "Using the last argument as
  keyword parameters is deprecated" warning.

### 1.0.0 (2020-05-18)

* Version 1.0.0 release! No changes since 0.5.0 except some small changes to the
  README.

### 0.5.0 (2020-05-17)

* Add `**context` argument to `#pack` method, exposed as `@context` in blocks
  passed to `field` and `trait`.
* Add `::with_context(&block)`, for accessing `@context` to use in additional
  DSL calls, or modify data fetching.
* Update README some re-organization and table of contents.

### 0.4.0 (2020-05-17)

* **_BREAKING CHANGE:_** `#pack_models` and `#pack_model` have been changed to
  private methods. In their place `Sequel::Packer#pack` has been changed to
  accept a dataset, an array of models or a single model, while still ensuring
  eager loading takes place.
* Add `self.precompute(&block)` for performing bulk computations outside of
  Packer paradigm.

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
