# $Id: tc_seller_lookup.rb,v 1.2 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestSellerLookup < AWSTest

  def test_seller_lookup

    sl = SellerLookup.new( 'A3QFR0K2KCB7EG' )
    sl_rg = ResponseGroup.new( 'Seller' )
    sl.response_group = sl_rg

    response = @req.search( sl )

    seller = response.kernel

    assert_equal( 'wherehouse', seller.nickname )

  end

  def test_seller_lookup_class_method

    response = Amazon::AWS.seller_lookup( 'A3QFR0K2KCB7EG' )

    seller = response.kernel

    assert_equal( 'wherehouse', seller.nickname )

  end

  def test_seller_lookup_class_method_block

    Amazon::AWS.seller_lookup( 'A3QFR0K2KCB7EG' ) do |r|

      seller = r.kernel

      assert_equal( 'wherehouse', seller.nickname )

    end
  end

end
