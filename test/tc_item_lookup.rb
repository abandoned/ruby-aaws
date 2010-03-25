# $Id: tc_item_lookup.rb,v 1.3 2010/02/20 17:15:17 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestItemLookup < AWSTest

  def test_item_lookup

    is = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC' } )
    is.response_group = @rg
    response = @req.search( is )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_item_lookup_class_method

    response = Amazon::AWS.item_lookup( 'ASIN', { 'ItemId' => 'B000AE4QEC' } )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_item_search_class_method_block

    Amazon::AWS.item_lookup( 'ASIN', { 'ItemId' => 'B000AE4QEC' } ) do |r|

      results = r.kernel

      # Ensure we got some actual results back.
      #
      assert( results.size > 0 )
    end
  end

end
