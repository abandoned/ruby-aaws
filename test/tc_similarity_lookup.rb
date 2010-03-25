# $Id: tc_similarity_lookup.rb,v 1.2 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestSimilarityLookup < AWSTest

  def test_similarity_lookup

    sl = SimilarityLookup.new( [ 'B000AE4QEC', 'B000051WBE' ] )
    sl_rg = ResponseGroup.new( :Subjects )
    sl.response_group = sl_rg

    response = @req.search( sl )

    items = response.similarity_lookup_response[0].items

    assert_match( /^\w+/, items.item[0].subjects.subject[0] )
    assert_match( /^\w+/, items.item[1].subjects.subject[0] )

  end

  def test_similarity_lookup_class_method

    response = Amazon::AWS.similarity_lookup( [ 'B000AE4QEC', 'B000051WBE' ] )

    items = response.similarity_lookup_response[0].items

    assert_match( /^http:/, items.item[0].detail_page_url )
    assert_match( /^http:/, items.item[1].detail_page_url )

  end

  def test_item_search_class_method_block

    Amazon::AWS.similarity_lookup( [ 'B000AE4QEC', 'B000051WBE' ] ) do |r|

    items = r.similarity_lookup_response[0].items

    assert_match( /^http:/, items.item[0].detail_page_url )
    assert_match( /^http:/, items.item[1].detail_page_url )

    end

  end

end
