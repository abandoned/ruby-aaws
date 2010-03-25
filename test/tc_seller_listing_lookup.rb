# $Id: tc_seller_listing_lookup.rb,v 1.2 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestSellerListingLookup < AWSTest

  def test_seller_listing_lookup

    sll = SellerListingLookup.new( 'AP8U6Y3PYQ9VO', :ASIN,
				   { :Id => 'B0009RRRC8' } )
    sll_rg = ResponseGroup.new( 'SellerListing' )
    sll.response_group = sll_rg

    response = @req.search( sll )

    item = response.kernel

    assert_equal( 'actionrecords', item.seller.nickname )

  end

  def test_seller_listing_lookup_class_method

    response = Amazon::AWS.seller_listing_lookup( 'AP8U6Y3PYQ9VO', :ASIN,
						  { :Id => 'B0009RRRC8' } )

    item = response.kernel

    assert_equal( 'actionrecords', item.seller.nickname )

  end

  def test_seller_listing_lookup_class_method_block

    Amazon::AWS.seller_listing_lookup( 'AP8U6Y3PYQ9VO', :ASIN,
				       { :Id => 'B0009RRRC8' } ) do |r|

      item = r.kernel

      assert_equal( 'actionrecords', item.seller.nickname )

    end
  end

end
