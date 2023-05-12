# Suppress all warnings coming from libraries.
$VERBOSE = nil

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "sequel/packer"

require 'sequel'
require 'awesome_print'
require 'pry'
require 'pry-byebug'

require_relative './models'

require "minitest/autorun"
