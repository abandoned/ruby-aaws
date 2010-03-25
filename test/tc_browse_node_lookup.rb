# $Id: tc_browse_node_lookup.rb,v 1.3 2010/02/20 17:15:17 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestBrowseNodeLookup < AWSTest

  def test_browse_node_lookup

    bnl = BrowseNodeLookup.new( 694212 )
    rg = ResponseGroup.new( :BrowseNodeInfo )
    bnl.response_group = rg

    response = @req.search( bnl )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_browse_node_lookup_class_method

    response = Amazon::AWS.browse_node_lookup( 694212 )

    results = response.kernel

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_browse_node_lookup_class_method_block

    Amazon::AWS.browse_node_lookup( '694212' ) do |r|

      results = r.kernel

      # Ensure we got some actual results back.
      #
      assert( results.size > 0 )
    end
  end

end
