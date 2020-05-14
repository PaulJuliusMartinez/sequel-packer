# Sequel::Packer

`Sequel::Packer` is a Ruby JSON serialization library to be used with the Sequel
ORM offering the following features:

* *Declarative:* Define the shape of your serialized data with a simple,
  straightforward DSL.
* *Flexible:* Certain contexts require different data. Packers provide an easy
  way to opt-in to serializing certain data only when you need it. The library
  also provides convenient escape hatches when you need to do something not
  explicitly supported by the API.
* *Reusable:* The Packer library naturally composes well with itself. Nested
  data can be serialized in the same way no matter what endpoint it's fetched
  from.
* *Efficient:* When not using Sequel's
  [`TacticalEagerLoading`](https://sequel.jeremyevans.net/rdoc-plugins/classes/Sequel/Plugins/TacticalEagerLoading.html)
  plugin, the Packer library will intelligently determine which associations
  and nested associations it needs to eager load in order to avoid any N+1 query
  issues.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sequel-packer'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sequel-packer

## Usage

Suppose we have the following basic database schema:

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
After validating the user id, we end up with the Sequel dataset represting the
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
CommentPacker.new.pack(recent_comments)
=> [
  {id: 536, content: "Great post, man!"},
  {id: 436, content: "lol"},
  {id: 413, content: "What a story..."},
]
```

### Packing associations by nesting Packers

Now, suppose that we want to fetch a post and all of its comments. We can do
this by defining another packer for Post that uses the CommentPacker:

```ruby
class PostPacker < Sequel::Packer
  model Post

  field :id
  field :title
  field :content
  field :comments, CommentPacker
end
```

Since `post.comments` is an array of Sequel::Models and not a primitive value,
we must tell the Packer how to serialize them using another packer. This is
what the second argument in `field :comments, CommentPacker` is doing.

We can then use this as follows:

```ruby
PostPacker.new.pack(Post.order(:id.desc).limit(1))
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
PostPacker instead, but then we'd have to redeclare all the other fields we want
on a packed Comment:

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
of defining a totally new packer, we can extend the CommentPacker as follows:

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

To use a trait, simply pass it in when creating the packer instance:

```ruby
# Without the trait
CommentPacker.new.pack(Comment.dataset)
=> [
  {id: 536, content: "Great post, man!"},
  ...
]

# With the trait
CommentPacker.new(:author).pack(Comment.dataset)
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

### `self.model(sequel_model_class)`

The beginning of each Packer class must begin with `model MySequelModel`, which
specifies which Sequel Model this Packer class will serialize. This is mostly
to catch certain errors at load time, rather than at run time.

### `self.field(column_name)` (or `self.field(method_name)`)

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

### `self.field(key, &block)`

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

### `self.field(association, packer_class, *traits)`

A Sequel association (defined in the model file using `one_to_many`, or
`many_to_one`, etc.), can be packed using another Packer class, possibly with
multiple traits specified. A similar output could be generated by doing:

```ruby
field :association do |model|
  packer_class.new(*traits).pack(model.association_dataset)
end
```

Though this version of course would result in many more queries to the database,
which are not required when using the shorthand form, and also requires creating
a new instance of `packer_class` for every packed model.

### `self.field(&block)`

Passing a block but no `key` to `field` allows for arbitrary manipulation of the
packed hash. The block will be passed the model and the partially packed hash.
One potential usage is for dynamic keys that cannot be determined at load time,
but otherwise it's meant as a general escape hatch.

```ruby
field do |model, hash|
  hash[model.compute_dynamic_key] = model.dynamic_value
end
```

### `self.trait(trait_name, &block)`

Define optional serialization behavior by defining additional fields within a
`trait` block. Traits can be opted into when initializing a packer by passing
the name of the trait as an argument:

```ruby
class MyPacker < Sequel::Packer
  model MyObj
  trait :my_trait do
    field :my_optional_field
  end
end

# packed objects don't have my_optional_field
MyPacker.new.pack(dataset)
# packed objects do have my_optional_field
MyPacker.new(:my_trait).pack(dataset)
```

Traits can also be used when packing associations by passing the name of the
traits after the packer class:

```ruby
class MyOtherPacker < Sequel::Packer
  model MyObj
  field :my_packers, MyPacker, :my_trait
end
```

### `self.eager(*associations)`

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

UserPacker.new.pack(User.dataset)
=> [
  {id: 123, num_posts: 7},
  {id: 456, num_posts: 3},
  ...
]
```

This helps prevent N+1 query problems when not using Sequel's
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

Keep in mind that this limits the association that gets used by ALL fields, so
if another field actually needs access to all the users posts, it might not make
sense to use `eager`.

Also, it's important to note that if `eager` is called multiple times, with
multiple procs, each proc will get applied to the dataset, likely resulting in
overly restrictive filtering.

### `self.set_association_packer(association, packer_class, *traits)`

See `self.pack_association(association, models)` below.

### `self.pack_association(association, models)`

The simplest way to pack an association is to use
`self.field(association, packer_class, *traits)`, but sometimes this doesn't do
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

#### Use a different field name than the name of the association
```ruby
set_association_packer :ugly_internal_names, InternalPacker
field :nice_external_names do |model|
  pack_association(:ugly_internal_names, model.ugly_internal_names)
end
```

#### Pack a single instance of a `one_to_many` association
```ruby
class PostPacker < Sequel::Packer
  set_association_packer :comments, CommentPacker
  field :top_comment do |model|
    pack_association(:comments, model.comments.max_by(&:num_likes))
  end
end
```


### `initialize(*traits)`

When creating an instance of a Packer class, pass in any traits desired to
specify what additional data should be packed, if any.

### `pack(dataset)`

After creating a new instance of a Packer class, call `packer.pack(dataset)` to
materialize a dataset and convert it to an array of packed Ruby hashes.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake test` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/PaulJuliusMartinez/sequel-packer.


## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
