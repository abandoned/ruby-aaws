# $Id: tc_list_search.rb,v 1.3 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestListSearch < AWSTest

  def test_list_search

    @req.locale = 'us'
    ls = ListSearch.new( 'WishList', { 'Name' => 'Peter Duff' } )
    ls_rg = ResponseGroup.new( :ListInfo )
    ls.response_group = ls_rg

    response = @req.search( ls )

    lists = response.kernel

    assert( lists.collect { |l| l.list_id }.flatten.include?( '1L88A4AXYF5QR' ) )

  end

  def test_list_search_class_method

    response = Amazon::AWS.list_search( 'WishList', { :Name => 'Peter Duff' } )

    lists = response.kernel

    assert( lists.size > 5 )

  end

  def test_item_search_class_method_block

    Amazon::AWS.list_search( 'WishList', { 'Name' => 'Peter Duff' } ) do |r|

      lists = r.kernel

      assert( lists.size > 5 )
    end
  end

end
