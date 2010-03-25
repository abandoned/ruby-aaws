# $Id: tc_tag_lookup.rb,v 1.2 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestTagLookup < AWSTest

  def test_tag_lookup

    @req.locale = 'us'
    tl = TagLookup.new( 'Awful' )
    tl_rg = ResponseGroup.new( :Tags, :TagsSummary )
    tl.response_group = tl_rg

    response = @req.search( tl )

    tag = response.kernel

    assert_equal( '2005-11-21 16:46:53', tag.first_tagging.time )

  end

end
