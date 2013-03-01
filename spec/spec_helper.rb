require "rubygems"
require "bundler"
Bundler.setup(:default, :test)

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'insano_image_resizer'
require 'fileutils'
require 'pry'
require 'pry-nav'
require 'pry-stack_explorer'

# Requires supporting files with custom matchers and macros, etc,
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

SAMPLES_DIR = Pathname.new(File.expand_path(File.dirname(__FILE__) + '/../samples')) unless defined?(SAMPLES_DIR)
