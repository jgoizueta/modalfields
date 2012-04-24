require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'
require 'shoulda'
require 'active_support'
require 'active_record'
require 'logger'

require 'active_support/core_ext/hash'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'modalfields'

class Test::Unit::TestCase
end

ENV['RAILS_ENV'] = 'test'
ENV['RAILS_ROOT'] ||= File.dirname(__FILE__) # + '/../../../..'

# require File.expand_path(File.join(ENV['RAILS_ROOT'], 'config/environment.rb'))

module Rails
  def self.root
    ENV['RAILS_ROOT']
  end
  def version
    ActiveRecord::VERSION::STRING
  end
end

def load_schema
  config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml')).with_indifferent_access
  ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")

  db_adapter = ENV['DB']

  # no db passed, try one of these fine config-free DBs before bombing.
  db_adapter ||=
    begin
      require 'rubygems'
      require 'sqlite3'
      'sqlite3'
      rescue MissingSourceFile
    end

  if db_adapter.nil?
    raise "No DB Adapter selected. Pass the DB= option to pick one, or install Sqlite3."
  end

  require File.dirname(__FILE__) + '/create_database'
  create_database config[db_adapter]

  ActiveRecord::Base.establish_connection(config[db_adapter])
  load(File.dirname(__FILE__) + "/schema.rb")
  require File.dirname(__FILE__) + '/../lib/modalfields'
  ModalFields.enable
end