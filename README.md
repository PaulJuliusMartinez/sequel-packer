# Sequel::Packer

`Sequel::Packer` is a Ruby JSON serialization library to be used with the [Sequel
ORM](https://github.com/jeremyevans/sequel) offering the following features:

* **Declarative:** Define the shape of your serialized data with a simple,
  straightforward DSL.
* **Flexible:** Certain contexts require different data. Packers provide an easy
  way to opt-in to serializing certain data only when you need it. The library
  also provides convenient escape hatches when you need to do something not
  explicitly supported by the API.
* **Reusable:** The Packer library naturally composes well with itself. Nested
  data can be serialized in the same way no matter what endpoint it's fetched
  from.
* **Efficient:** When not using Sequel's
  [`TacticalEagerLoading`](https://sequel.jeremyevans.net/rdoc-plugins/classes/Sequel/Plugins/TacticalEagerLoading.html)
  plugin, the Packer library will intelligently determine which associations
  and nested associations it needs to eager load in order to avoid any N+1 query
  issues.

- [Example](#example)
- [Getting Started](#getting-started)
  - [Installation](#installation)
  - [Example Schema](#example-schema)
  - [Basic Fields](#basic-fields)
  - [Packing Associations by Nesting Packers](#packing-associations-by-nesting-packers)
  - [Traits](#traits)
- [API Reference](#api-reference)
  - [Using a Packer](#using-a-packer)
  - [Defining a Packer](#defining-a-packer)
    - [`self.model(sequel_model_class)`](#selfmodelsequel_model_class)
    - [`self.field(column_name)` (or `self.field(method_name)`)](#selffieldcolumn_name-or-selffieldmethod_name)
    - [`self.field(key, &block)`](#selffieldkey-block)
    - [`self.field(association, subpacker, *traits)`](#selffieldassociation-subpacker-traits)
    - [`self.field(&block)`](#selffieldblock)
    - [`self.trait(trait_name, &block)`](#selftraittrait_name-block)
    - [`self.eager(*associations)`](#selfeagerassociations)
    - [`self.set_association_packer(association, subpacker, *traits)`](#selfset_association_packerassociation-subpacker-traits)
    - [`self.pack_association(association, models)`](#selfpack_associationassociation-models)
    - [`self.precompute(&block)`](#selfprecomputeblock)
  - [Context](#context)
    - [`self.with_context(&block)`](#selfwith_contextblock)
- [Contributing](#contributing)
  - [Development](#development)
  - [Releases](#releases)
- [Attribution](#attribution)
- [License](#license)

## Example

`Sequel::Packer` uses your existing `Sequel::Model` declarations and leverages
the use of associations to efficiently serialize data.

```ruby
class User < Sequel::Model(:users)
  one_to_many :posts
end
class Post < Sequel::Model(:posts); end
```

Packer definitions use a simple domain-specific language (DSL) to declare which
fields to serialize:

```ruby
class PostPacker < Sequel::Packer
  model Post

  field :id
  field :title

  trait :truncated_content do
    field :truncated_content do |post|
      post.content[0..Post::PREVIEW_LENGTH]
    end
  end
end

class UserPacker < Sequel::Packer
  model User

  field :id
  field :name

  trait :posts do
    field :posts, PostPacker, :truncated_content
  end
end
```

Once defined, Packers are easy to use; just call `.pack` and pass in a Sequel
dataset, an array of models, or a single model, and get back Ruby hashes.
Simply call `to_json` on the result!

```ruby
UserPacker.pack(User.dataset)
=> [
  {id: 1, name: 'Paul'},
  {id: 2, name: 'Julius'},
  ...
]

UserPacker.pack(User[1], :posts)
=> {
  id: 1,
  name: 'Paul',
  posts: [
    {
      id: 15,
      title: 'Announcing Sequel::Packer!',
      truncated_content: 'Sequel::Packer is a new gem...',
    },
    {
      id: 21,
      title: 'Postgres Internals',
      truncated_content: 'I never quite understood autovacuum...',
    },
    ...
  ],
}
```

## Getting Started

This section will explain the basic use of `Sequel::Packer`. Check out the [API
Reference](#api-reference) for an exhaustive coverage of the API and more
detailed documentation.

### Installation

Add this line to your application's Gemfile:

```ruby
gem 'sequel-packer'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sequel-packer

### Example Schema

Most of the following examples will use the following database schema:

```ruby
DB.create_table(:users) do
  primary_key :id
  String :name
end

DB.create_table(:posts) do
  primary_key :id
  foreign_key :author_id, :users
  String :title
  String :content
end

DB.create_table(:comments) do
  primary_key :id
  foreign_key :author_id, :users
  foreign_key :post_id, :posts
  String :content
end

class User < Sequel::Model(:users)
  one_to_many :posts, key: :author_id, class: :Post
end
class Post < Sequel::Model(:posts)
  one_to_many :comments, key: :post_id, class: :Comment
end
class Comment < Sequel::Model(:comments)
  many_to_one :author, key: :author_id, class: :User
end
```

### Basic Fields

Suppose an endpoint wants to fetch all the ten most recent comments by a user.
After validating the user id, we end up with the Sequel dataset representing the
data we want to return:

```ruby
recent_comments = Comment
  .where(author_id: user_id)
  .order(:id.desc)
  .limit(10)
```

We can define a Packer class to serialize just fields we want to, using a
custom DSL:

```ruby
class CommentPacker < Sequel::Packer
  model Comment

  field :id
  field :content
end
```

This can then be used as follows:

```ruby
CommentPacker.pack(recent_comments)
=> [
  {id: 536, content: "Great post, man!"},
  {id: 436, content: "lol"},
  {id: 413, content: "What a story..."},
]
```

### Packing Associations by Nesting Packers

Now, suppose that we want to fetch a post and all of its comments. We can do
this by defining another packer for `Post` that uses the `CommentPacker`:

```ruby
class PostPacker < Sequel::Packer
  model Post

  field :id
  field :title
  field :content
  field :comments, CommentPacker
end
```

Since `post.comments` is an array of `Sequel::Models` and not a primitive value,
we must tell the Packer how to serialize them using another packer. The second
argument in `field :comments, CommentPacker` tells the `PostPacker` to use the
pack those comments using the `CommentPacker`.

We can then use this as follows:

```ruby
PostPacker.pack(Post[validated_id])
=> [
  {
    id: 682,
    title: "Announcing sequel-packer",
    content: "I've written a new gem...",
    comments: [
      {id: 536, content: "Great post, man!"},
      {id: 541, content: "Incredible, this solves my EXACT problem!"},
      ...
    ],
  }
]
```

### Traits

But suppose we want to be able to show who authored each comment on the post. We
first have to define a packer for users:

```ruby
class UserPacker < Sequel::Packer
  model User

  field :id
  field :name
end
```

We could now define a new packer, `CommentWithAuthorPacker`, and use that in the
`PostPacker` instead, but then we'd have to redeclare all the other fields we
want on a packed `Comment`:

```ruby
class CommentWithAuthorPacker < Sequel::Packer
  model Comment

  field :author, UserPacker

  # Also defined in CommentPacker!
  field :id
  field :content
end

class PostPacker < Sequel::Packer
  ...

  # Eww!
- field :comments, CommentPacker
+ field :comments, CommentWithAuthorPacker
end
```

Declaring these fields in two places could cause them to get out of sync
as more fields are added. Instead, we will use a _trait_. A _trait_ is a
way to define a set of fields that we only want to pack sometimes. Instead
of defining a totally new packer, we can extend the `CommentPacker` as follows:

```ruby
class CommentPacker < Sequel::Packer
  model Comment

  field :id
  field :content

+ trait :author do
+   field :author, UserPacker
+ end
end
```

To use a trait, simply pass it in when calling `pack`:

```ruby
# Without the trait
CommentPacker.pack(Comment.dataset)
=> [
  {id: 536, content: "Great post, man!"},
  ...
]

# With the trait
CommentPacker.pack(Comment.dataset, :author)
=> [
  {
    id: 536,
    content: "Great post, man!",
    author: {id: 1, name: "Paul Martinez"},
  },
  ...
]
```

To use a trait when packing an association in another packer, simply include
the name of the trait as additional argument to `field`. Thus, to modify our
PostPacker to pack comments with their authors we make the following change:

```ruby
class PostPacker < Sequel::Packer
  model Post

  field :id
  field :title
  field :content

- field :comments, CommentPacker
+ field :comments, CommentPacker, :author
end
```

While the basic Packer DSL is convenient, traits are the things that make
Packers so powerful. Each packer should define a small set of fields that every
endpoint needs, but then traits can be used to pack additional data only when
it's needed.

## API Reference

Custom packers are written by creating subclasses of `Sequel::Packer`. This
class defines a DSL for declaring how a Sequel Model will be converted into a
plain Ruby hash.

### Using a Packer

Using a Packer is dead simple. There's a single class method:

```ruby
self.pack(data, *traits, **context)
```

`data` can be in the form of a Sequel dataset, an array of Sequel models, or
a single Sequel model. No matter which form the data is passed in, the Packer
class will ensure nested data is efficiently loaded.

To pack additional fields defined in a trait, pass the name of the trait as an
additional argument, e.g., `UserPacker.pack(users, :recent_posts)` to include
recent posts with each user.

Finally, additional context can be provided to the Packer by passing additional
keyword arguments to `pack`. This context is handled opaquely by the Packer, but
it can be accessed in the blocks passed to `field` declarations. Common uses of
`context` include passing in the current user making a request, or passing in
additional precomputed data.

The implementation of `pack` is very simple. It creates an instance of a Packer,
by passing in the traits and the context, then calls `pack` on that instance,
and passes in the data:

```ruby
def self.pack(data, *traits, **context)
  return nil if !data # small easy optimization to avoid unnecessary work
  new(*traits, **context).pack(data)
end
```

It simply combines a constructor and single exposed instance method:

#### `initialize(*traits, **context)`

#### `pack(data)`

One instantiated, the same Packer could be used to pack data multiple times.
This is unlikely to be needed, but the functionality is there.

### Defining a Packer

#### `self.model(sequel_model_class)`

The beginning of each Packer class must begin with `model MySequelModel`, which
specifies which Sequel Model this Packer class will serialize. This is mostly
to catch certain errors at load time, rather than at run time:

```ruby
class UserPacker < Sequel::Packer
  model User
  ...
end
```

#### `self.field(column_name)` (or `self.field(method_name)`)

Defining the shape of the outputted data is done using the `field` method, which
exists in four different variants. This first variant is the simplest. It simply
fetches the value of the column from the model and stores it in the outputted
hash under a key of the same name. Essentially `field :my_column` eventually
results in `hash[:my_column] = model.my_column`.

Sequel Models define accessor methods for each column in the underlying table,
so technically underneath the hood Packer is actually calling the sending the
method `column_name` to the model: `hash[:my_column] = model.send(:my_column)`.

This means that the result of any method can be serialized using
`field :method_name`. For example, suppose a User model has a `first_name` and
`last_name` column, and a helper method `full_name`:

```ruby
class User < Sequel::Model(:users)
  def full_name
    "#{first_name} #{last_name}"
  end
end
```

Then when `User.create(first_name: "Paul", last_name: "Martinez")` gets packed
with `field :full_name` specified, the outputted hash will contain
`full_name: "Paul Martinez"`.

#### `self.field(key, &block)`

A block can be passed to `field` to perform arbitrary computation and store the
result under the specified `key`. The block will be passed the model as a single
argument. Use this to call methods on the model that may take additional
arguments, or to "rename" a column.

Examples:

```ruby
class MyPacker < Sequel::Packer
  model MyModel

  field :friendly_public_name do |model|
    model.unfriendly_internal_name
  end

  # Shorthand for above
  field :friendly_public_name, &:unfriendly_internal_name

  field :foo do |model|
    model.bar(baz, quux)
  end
end
```

#### `self.field(association, subpacker, *traits)`

A Sequel association (defined in the model file using `one_to_many`, or
`many_to_one`, etc.), can be packed using another Packer class, possibly with
multiple traits specified. A similar output could be generated by doing:

```ruby
field :association do |model|
  subpacker.pack(model.association_dataset, *traits)
end
```

This form is very inefficient though, because it would result in a new subpacker
getting instantiated for every packed model. Additionally, unless the subpacker
is declared up-front, the Packer won't know to eager load that association,
potentially resulting in many unnecessary database queries.

#### `self.field(&block)`

Passing a block but no `key` to `field` allows for arbitrary manipulation of the
packed hash. The block will be passed the model and the partially packed hash.
One potential usage is for dynamic keys that cannot be determined at load time,
but otherwise it's meant as a general escape hatch.

```ruby
field do |model, hash|
  hash[model.compute_dynamic_key] = model.dynamic_value
end
```

#### `self.trait(trait_name, &block)`

Define optional serialization behavior by defining additional fields within a
`trait` block. Traits can be opted into when initializing a packer by passing
the name of the trait as an argument:

```ruby
class MyPacker < Sequel::Packer
  model MyObj
  field :id

  trait :my_trait do
    field :trait_field
  end
end

# packed objects don't have trait_field
MyPacker.pack(dataset)
=> [{id: 1}, {id: 2}, ...]
# packed objects do have trait_field
MyPacker.pack(dataset, :my_trait)
=> [{id: 1, trait_field: 'foo'}, {id: 2, trait_field: 'bar'}, ...]
```

Traits can also be used when packing associations by passing the name of the
traits after the packer class:

```ruby
class MyOtherPacker < Sequel::Packer
  model MyObj
  field :my_packers, MyPacker, :my_trait
end
```

#### `self.eager(*associations)`

When packing an association, a Packer will automatically ensure that association
is eager loaded, but there may be cases when an association will be accessed
that the Packer doesn't know about. In these cases you can tell the Packer to
eager load that data by calling `eager(*associations)`, passing in arguments
the exact same way you would to [`Sequel::Dataset.eager`](
https://sequel.jeremyevans.net/rdoc/classes/Sequel/Model/Associations/DatasetMethods.html#method-i-eager).

One case where this may be useful is for a "count" field, that just lists the
number of associated objects, but doesn't actually return them:

```ruby
class UserPacker < Sequel::Packer
  model User

  field :id

  eager(:posts)
  field(:num_posts) do |user|
    user.posts.count
  end
end

UserPacker.pack(User.dataset)
=> [
  {id: 123, num_posts: 7},
  {id: 456, num_posts: 3},
  ...
]
```

Using `eager` can help prevent N+1 query problems when not using Sequel's
[`TacticalEagerLoading`](https://sequel.jeremyevans.net/rdoc-plugins/classes/Sequel/Plugins/TacticalEagerLoading.html)
plugin.

Another use of `eager`, even when using `TacticalEagerLoading`, is to modify or
limit which records gets fetched from the database by using an eager proc. For
example, to only pack recent posts, published in the past month, we might do:

```
class UserPacker < Sequel::Packer
  model User

  field :id

  trait :recent_posts do
    eager posts: (proc {|ds| ds.where {created_at > Time.now - 1.month}})
    field :posts, PostIdPacker
  end
end
```

**IMPORTANT NOTE:** Eager procs are not guaranteed to be executed when passing
in models, rather than a dataset, to `pack`. Specifically, if the models already
have fetched the association, the Packer won't refetch it. Because of this, it's
good practice to use `set_association_packer` and `pack_association` (see next
section) in a `field` block and duplicate the filtering action.

Also keep in mind that this limits the association that gets used by ALL fields,
so if another field actually needs access to all the users posts, it might not
make sense to use `eager`.

Additionally, it's important to note that if `eager` is called multiple times,
with multiple procs, each proc will get applied to the dataset, likely resulting
in overly restrictive filtering.

#### `self.set_association_packer(association, subpacker, *traits)`

See `self.pack_association(association, models)` below.

#### `self.pack_association(association, models)`

The simplest way to pack an association is to use
`self.field(association, subpacker, *traits)`, but sometimes this doesn't do
exactly what we want. We may want to pack the association under a different key
than the name of the association. Or we may only want to pack some of the
associated models (and it may be difficult or impossible to express which subset
we want to pack using `eager`). Or perhaps we have a `one_to_many` association
and instead of packing an array, we want to pack a single associated object
under a key. The two methods, `set_association_packer` and `pack_association`
are designed to handle these cases.

First, we'll note that following are exactly equivalent:

```ruby
field :my_assoc, MyAssocPacker, :trait1, :trait2
```

and

```ruby
set_association_packer :my_assoc, MyAssocPacker, :trait1, :trait2
field :my_assoc do |model|
  pack_association(:my_assoc, model.my_assoc)
end
```

`set_association_packer` tells the Packer class that we will want to pack models
from a particular association using the designated Packer with the specified
traits. Declaring this ahead of time allows the Packer to ensure that the
association is eager loaded, as well as any nested associations used when using
the designated Packer with the specified traits.

`pack_association` can then be used in a `field` block to use that Packer after
the data has been fetched and we are actually packing the data. The key things
here are that we don't need to use the name of the association as the name of
the field, and that we can choose which models get serialized. If
`pack_association` is passed an array, it will return an array of packed models,
but if it is passed a single model, it will return just that packed model.

Examples:

##### Use a different field name than the name of the association
```ruby
set_association_packer :ugly_internal_names, InternalPacker
field :nice_external_names do |model|
  pack_association(:ugly_internal_names, model.ugly_internal_names)
end
```

##### Pack a single instance of a `one_to_many` association
```ruby
class PostPacker < Sequel::Packer
  set_association_packer :comments, CommentPacker
  field :top_comment do |model|
    pack_association(:comments, model.comments.max_by(&:num_likes))
  end
end
```

#### `self.precompute(&block)`

Occasionally packing a model may require a computation that doesn't fit in with
the rest of the Packer paradigm. This may be a Sequel query that is particularly
difficult to express as an association, or even a call to an external service.
If such a computation can be performed in bulk, then the `precompute` method can
be used as an entry point for that operation.

The `precompute` method will execute a given block and pass it all of the models
that will be packed using that packer. This block will be executed a single
time, even when called by a deeply nested packer.

The `precompute` block is `instance_exec`ed in the context of the packer
instance, the result of any computation can be saved in a simple instance
variable (`@precomputed_result`) and later referenced inside the blocks that are
passed to `field` methods.

As an example, suppose a video uploading platform performs additional video
processing on every uploaded video and exposes the status of that processing as
a separate service over the network, rather than directly with the upload
metadata in the database. `precompute` could be used as follows:

```ruby
class VideoUploadPacker < Sequel::Packer
  model VideoUpload

  precompute do |video_uploads|
    @processing_statuses = ResolutionService
      .get_status_bulk(ids: video_uploads.map(&:id))
  end

  field :id
  field :filename
  field :processing_status do |video_upload|
    @processing_statuses[video_upload.id]
  end
end
```

#### Instance method versions

In addition to the class method versions of `field`, `eager`,
`set_association_packer`, and `precompute`, there are also regular instance method
versions which take the exact same arguments. When writing a `trait` block, the
block is evaulated in the context of a new Packer instance and actually calls the
instance method versions instead.

### Context

In addition to the data to be packed, and a set of traits, the `pack` method
also accepts arbitrary keyword arguments. This is referred to as `context` is
handled opaquely by the Packer. The data passed in here is saved as the
`@context` instance variable, which is then accessible from within the blocks
passed to `field`, `trait`, and `precompute`, for whatever purpose. It is also
automatically passed to any nested subpackers.

The most common usage for context would be to pass in the current user making
a request. It could then be used to pack permission levels about records, for
example.

```ruby
class PostPacker < Sequel::Packer
  model Post

  eager :permissions
  field :access_level do |post|
    user_permission = post.permissions.find do |perm|
      perm.user_id == @context[:user].id
    end

    user_permission.access_level
  end
end
```

You might notice something inefficient about the above code. Even though we only
want to look at the user's permission record, we fetch ALL of the permission
records for each Post. Ideally we would filter the `permissions` association
dataset when we call `eager`, but we don't have access to `@context` at that
point. This leads to the final DSL method available when writing a Packer:

#### `self.with_context(&block)`

You can pass a block to `with_context` that will be executed as soon as a Packer
instance is constructed. The block can access `@context` and can also call the
standard Packer DSL methods, `field`, `eager`, etc.

The above example could then be made more efficient as follows:

```ruby
class PostPacker < Sequel::Packer
  model Post

- eager :permissions
+ with_context do
+   eager permissions: (proc {|ds| ds.where(user_id: @context[:user].id)})
+ end
end
```

A very tricky usage of `with_context` (and not recommended...) would be to
control the traits used on subpackers:

```ruby
class UserPacker < Sequel::Packer
  model User

  with_context do
    field :comments, CommentPacker, *@context[:comment_traits]
  end
end

UserPacker.pack(User.dataset, comment_traits: [])
=> [{comments: [{id: 7}, ...]}]
UserPacker.pack(User.dataset, comment_traits: [:author])
=> [{comments: [{id: 7, author: {id: 1, ...}}, ...]}]
UserPacker.pack(User.dataset, comment_traits: [:num_likes])
=> [{comments: [{id: 7, likes: 53}, ...]}]
```

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/PaulJuliusMartinez/sequel-packer.

### Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake test` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

### Releases

To release a new version, update the version number in
`lib/sequel/packer/version.rb`, update the `CHANGELOG.md` with new changes, then
run `rake release`, which which will create a git tag for the version, push git
commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Attribution

[Karthik Viswanathan](https://github.com/karthikv) designed the original API
of the Packer library while at [Affinity](https://www.affinity.co/). This
library is a ground up rewrite which defines a very similar API, but shares no
no code with the original implementation.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
