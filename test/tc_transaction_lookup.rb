# $Id: tc_transaction_lookup.rb,v 1.2 2010/02/20 17:15:19 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestTransactionLookup < AWSTest

  def test_transaction_lookup

    @req.locale = 'us'
    tl = TransactionLookup.new( '103-5663398-5028241' )
    tl_rg = ResponseGroup.new( :TransactionDetails )
    tl.response_group = tl_rg

    response = @req.search( tl )

    trans = response.kernel

    assert_equal( '2008-04-13T23:49:38', trans.transaction_date )

  end

end
