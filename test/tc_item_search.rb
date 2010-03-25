# encoding: ASCII-8BIT
#
# $Id: tc_item_search.rb,v 1.8 2010/02/20 23:57:26 ianmacd Exp $
#
# The encoding at the top of this file is necessary for Ruby 1.9, which will
# otherwise choke with 'invalid multibyte char (US-ASCII)' when it reads the
# ISO-8859-1 encoded accented 'e' in the test_item_search_iso_8859_15 method.

require 'test/unit'
require './setup'

class TestItemSearch < AWSTest

  def test_item_search_iso_8859_15

    # Ensure that character set encoding works properly by manually trying
    # ISO-8859-15, a.k.a. Latin-15.
    #
    @req.encoding = 'iso-8859-15'

    str = 'Caf�'
    is = ItemSearch.new( 'Books', { 'Title' => str } )
    response = @req.search( is )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_item_search_utf8

    # Manually set UTF-8 encoding.
    #
    @req.encoding = 'utf-8'

    str = 'Café'
    is = ItemSearch.new( 'Books', { 'Title' => str } )
    response = @req.search( is )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_item_search_obsolete_rg_passing

    # Manually set UTF-8 encoding.
    #
    @req.encoding = 'utf-8'

    str = 'Café'
    is = ItemSearch.new( 'Books', { 'Title' => str } )

    assert_raise( Amazon::AWS::ObsolescenceError ) do
      response = @req.search( is, @rg )
    end

  end

  def test_item_search_multiple_pages

    @req.encoding = 'utf-8'
    is = ItemSearch.new( 'Books', { 'Title' => 'programming' } )
    responses = @req.search( is, 5 )

    results = []
    responses.each { |response| results += response.kernel }

    # Ensure we got more than 10 results back.
    #
    assert( results.size > 10 )

  end

  def test_item_search_class_method

    response = Amazon::AWS.item_search( 'Books', { 'Title' => 'programming' } )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_item_search_class_method_block

    Amazon::AWS.item_search( 'Books', { 'Title' => 'programming' } ) do |r|

      results = r.kernel

      # Ensure we got some actual results back.
      #
      assert( results.size > 0 )
    end
  end

end
