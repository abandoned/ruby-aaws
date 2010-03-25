# $Id: setup.rb,v 1.6 2009/09/16 22:31:07 ianmacd Exp $
#

# Attempt to load Ruby/AWS using RubyGems.
#
begin 
  require 'rubygems'
  gem 'ruby-aws'
rescue LoadError
  # Either we don't have RubyGems or we don't have a gem of Ruby/AWS.
end

# Require the essential library, be it via RubyGems or the default way.
#
require 'amazon/aws/search'

include Amazon::AWS
include Amazon::AWS::Search

class AWSTest < Test::Unit::TestCase

  # Figure out where the user config file is.
  #
  home = ENV['AMAZONRCDIR'] ||
         ENV['HOME'] || ENV['HOMEDRIVE'] + ENV['HOMEPATH'] ||
         ENV['USERPROFILE']
  user_rcfile = ENV['AMAZONRCFILE'] || '.amazonrc'
  rc = File.expand_path( File.join( home, user_rcfile ) )

  # Replace the locale with UK.
  #
  lines = File.open( rc ) { |f| f.readlines }
  lines.each { |l| l.sub!( /(locale\s*=\s*['"])..(['"])/, "\\1uk\\2" ) }
 
  # Write a new config file for the purpose of unit testing.
  #
  test_rc = File.join( Dir.pwd, '.amazonrc' )
  File.open( test_rc, 'w' ) { |f| f.puts lines } unless File.exist?( test_rc )

  # Make sure the unit tests use the new config file.
  #
  ENV['AMAZONRCDIR'] = Dir.pwd

  def setup
    @rg = ResponseGroup.new( :Small )
    @req = Request.new
    @req.locale = 'uk'
    @req.cache = false
    @req.encoding = 'utf-8'
  end

  # The default_test method needs to be removed before Ruby 1.9.0.
  #
  undef_method :default_test if method_defined? :default_test
 
end
