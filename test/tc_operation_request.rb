# $Id: tc_operation_request.rb,v 1.2 2010/02/20 17:15:18 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestOperationRequest < AWSTest

  def test_operation_request
    is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
    is_rg = ResponseGroup.new( 'Request' )
    is.response_group = is_rg

    response = @req.search( is )

    # Same again with Symbols.
    #
    is = ItemSearch.new( :Books, { :Title => 'Ruby' } )
    is_rg = ResponseGroup.new( :Request )
    is.response_group = is_rg

    response = @req.search( is )
 
    # Make sure undocumented AWSObject#results provides an accurate shortcut
    # to the most interesting part of the data returned by AWS.
    #
    assert_equal( response.item_search_response[0].items[0].item,
		  response.kernel )

    # Ensure response is an Amazon::AWS::AWSObject.
    #
    assert_instance_of( Amazon::AWS::AWSObject, response )

    # Ensure non-existent instance variables return nil.
    #
    assert_nil( response.foo_bar_baz )

    # Ensure top level of response is an Amazon::AWS::AWSArray.
    #
    assert_instance_of( Amazon::AWS::AWSArray, response.item_search_response )

    # Ensure delegation of method from AWSArray to single element.
    #
    assert_equal( response.item_search_response[0].operation_request,
		  response.item_search_response.operation_request )

    # Test for correct user-agent in response.
    #
    assert_equal( Amazon::AWS::USER_AGENT,
		  response.item_search_response[0].operation_request[0].
		  http_headers[0].header[0].attrib['value'] )

    # Ensure that the correct version of the AWS API was requested.
    #
    response.item_search_response[0].operation_request[0].arguments[0].
    argument.each do |arg|
      next unless arg.attrib['name'] == 'Version'
      assert_equal( Amazon::AWS::SERVICE['Version'], arg.attrib['value'] )
      break
    end

  end

end
