# $Id: tc_list_lookup.rb,v 1.4 2010/02/20 17:15:17 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestListLookup < AWSTest

  def test_list_lookup

    @req.locale = 'us'
    ll = ListLookup.new( '3TV12MGLOJI4R', :WishList )
    ll_rg = ResponseGroup.new( :ListInfo )
    ll.response_group = ll_rg

    response = @req.search( ll )

    list = response.kernel

    assert_equal( '2008-06-30', list.date_created )

  end

  def test_list_lookup_all_pages

    @req.locale = 'uk'
    ll = ListLookup.new( '1OPRRUVZVU9BE', 'WishList' )
    ll_rg = ResponseGroup.new( 'ListInfo', 'Small' )
    ll.response_group = ll_rg

    response = @req.search( ll, :ALL_PAGES )

    list = response.collect { |r| r.list_lookup_response[0].lists[0].list }
    reported_items = list[0].total_items.to_i
    items = list.collect { |page| page.list_item }.flatten

    assert_equal( reported_items, items.size )
  end

  def test_list_lookup_class_method

    response = Amazon::AWS.list_lookup( 'R35BA7X0YD3YP', 'Listmania' )

    list = response.kernel

    assert_equal( 'examples of perfection', list.list_name )

  end

  def test_item_search_class_method_block

    Amazon::AWS.list_lookup( 'R35BA7X0YD3YP', :Listmania ) do |r|

      list = r.kernel

      assert_equal( 'examples of perfection', list.list_name )
    end
  end

end
