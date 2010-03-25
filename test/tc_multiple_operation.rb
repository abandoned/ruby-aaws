# $Id: tc_multiple_operation.rb,v 1.4 2010/02/20 17:32:12 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestMultipleOperation < AWSTest

  # Because exception classes aren't created until an exception occurs, we
  # need to create the ones we wish to test for now, otherwise we can't refer
  # to them in our code without causing an 'uninitialized constant' error.
  #
  Amazon::AWS::Error.const_set( 'ExceededMaxBatchRequestsPerOperation',
				Class.new( Amazon::AWS::Error::AWSError ) )
  Amazon::AWS::Error.const_set( 'ExceededMaxMultiOpOperations',
				Class.new( Amazon::AWS::Error::AWSError ) )

  def test_unbatched_same_class
    il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC',
				   'MerchantId' => 'Amazon' } )
    il2 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000051WBE',
				    'MerchantId' => 'Amazon' } )
    il3 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B00061F8LO',
				    'MerchantId' => 'Amazon' } )
    il4 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B002DESIE6',
				    'MerchantId' => 'Amazon' } )

    il.response_group = ResponseGroup.new( :Large )
    il2.response_group = ResponseGroup.new( :Small )

    # Create a multiple operation of the two ItemLookup operations.
    #
    mo = MultipleOperation.new( il, il2 )
    response = @req.search( mo )
    mor = response.item_lookup_response[0]

    # Ensure our separate response groups were used.
    #
    arguments = mor.operation_request.arguments.argument

    il_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.1.ResponseGroup'
    end[0]

    il2_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.2.ResponseGroup'
    end[0]

    assert_equal( 'Large', il_rg.attrib['value'] )
    assert_equal( 'Small', il2_rg.attrib['value'] )

    # Ensure we received a MultiOperationResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemLookupResponse, mor )
    
    il_set = mor.items
    il_arr1 = il_set[0].item
    il_arr2 = il_set[1].item

    # Ensure that there are two <ItemSet>s for the ItemLookup, because it was
    # a batched operation.
    #
    assert_equal( 2, il_set.size )

    # Assure that all item sets have some results.
    #
    assert( il_arr1.size > 0 )
    assert( il_arr2.size > 0 )

    mo = MultipleOperation.new( il, il2, il3 )

    # Attempt to perform the search.
    #
    assert_raise( Amazon::AWS::Error::ExceededMaxBatchRequestsPerOperation ) do
      @req.search( mo )
    end

    mo = MultipleOperation.new( il, il2, il3, il4 )
    assert_raise( Amazon::AWS::Error::ExceededMaxBatchRequestsPerOperation ) do
      @req.search( mo )
    end
  end


  def test_batched_same_class
    il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC',
				   'MerchantId' => 'Amazon' } )
    il2 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000051WBE',
				    'MerchantId' => 'Amazon' } )
    il3 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B00061F8LO',
				    'MerchantId' => 'Amazon' } )
    il4 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B002DESIE6',
				    'MerchantId' => 'Amazon' } )

    il.response_group = ResponseGroup.new( :Large )
    il2.response_group = ResponseGroup.new( :Small )

    il.batch( il2 )
    il3.batch( il4 )

    # Create a multiple operation of the two batched operations.
    #
    mo = MultipleOperation.new( il, il3 )

    # Attempt to perform the search.
    #
    assert_raise( Amazon::AWS::Error::ExceededMaxBatchRequestsPerOperation ) do
      @req.search( mo )
    end

    # Create a multiple operation of a single operation, plus a batched.
    #
    mo = MultipleOperation.new( il2, il3 )

    # Attempt to perform the search.
    #
    assert_raise( Amazon::AWS::Error::ExceededMaxBatchRequestsPerOperation ) do
      @req.search( mo )
    end

    # Create a multiple operation of a batched operation, plus a single.
    #
    mo = MultipleOperation.new( il, il4 )

    # Attempt to perform the search.
    #
    assert_raise( Amazon::AWS::Error::ExceededMaxBatchRequestsPerOperation ) do
      @req.search( mo )
    end

  end


  def test_unbatched_different_class
    il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC',
				   'MerchantId' => 'Amazon' } )
    is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
    bnl = BrowseNodeLookup.new( 694212 )

    il.response_group = ResponseGroup.new( :Medium )
    is.response_group = ResponseGroup.new( :Medium, :Tags )
    bnl.response_group = ResponseGroup.new( :BrowseNodeInfo )

    # Create a multiple operation of the ItemSearch operation and the
    # ItemLookup operation.
    #
    mo = MultipleOperation.new( is, il )
    response = @req.search( mo )
    mor = response.multi_operation_response[0]

    # Ensure our separate response groups were used.
    #
    arguments = mor.operation_request.arguments.argument

    il_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.1.ResponseGroup'
    end[0]

    is_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemSearch.1.ResponseGroup'
    end[0]

    assert_equal( 'Medium', il_rg.attrib['value'] )
    assert_equal( 'Medium,Tags', is_rg.attrib['value'] )

    # Ensure we received a MultiOperationResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::MultiOperationResponse, mor )
    
    # Ensure response contains an ItemSearchResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemSearchResponse,
		        mor.item_search_response[0] )

    # Ensure response also contains an ItemLookupResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemLookupResponse,
		        mor.item_lookup_response[0] )
 
    is_set = mor.item_search_response[0].items
    il_set = mor.item_lookup_response[0].items
    is_arr = is_set.item
    il_arr = il_set.item

    # Ensure that there's one <ItemSet> for the ItemSearch.
    #
    assert_equal( 1, is_set.size )

    # Ensure that there's one <ItemSet> for the ItemLookup.
    #
    assert_equal( 1, il_set.size )

    # Assure that all item sets have some results.
    #
    assert( is_arr.size > 0 )
    assert( il_arr.size > 0 )

    mo = MultipleOperation.new( is, il, bnl )
    assert_raise( Amazon::AWS::Error::ExceededMaxMultiOpOperations ) do
      @req.search( mo )
    end
  end


  def test_batched_different_class
    il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC',
				   'MerchantId' => 'Amazon' } )
    il2 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000051WBE',
				    'MerchantId' => 'Amazon' } )
    il3 = ItemLookup.new( 'ASIN', { 'ItemId' => 'B00061F8LO',
				    'MerchantId' => 'Amazon' } )
    is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
    is2 = ItemSearch.new( 'Music', { 'Artist' => 'Dead Can Dance' } )
    bnl = BrowseNodeLookup.new( 694212 )

    il.response_group = ResponseGroup.new( :Medium )
    il2.response_group = ResponseGroup.new( :Large )
    is.response_group = ResponseGroup.new( :Medium, :Tags )
    is2.response_group = ResponseGroup.new( :Small, :Reviews )
    bnl.response_group = ResponseGroup.new( :BrowseNodeInfo )

    # Create a multiple operation of two batched ItemSearch operations and two
    # batched ItemLookup operations.
    #
    il.batch( il2 )
    is.batch( is2 )

    mo = MultipleOperation.new( [ is, il ] )
    response = @req.search( mo )
    mor = response.multi_operation_response[0]

    # Ensure our separate response groups were used.
    #
    arguments = mor.operation_request.arguments.argument

    il_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.1.ResponseGroup'
    end[0]

    il2_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.2.ResponseGroup'
    end[0]

    is_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemSearch.1.ResponseGroup'
    end[0]

    is2_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemSearch.2.ResponseGroup'
    end[0]

    assert_equal( 'Medium', il_rg.attrib['value'] )
    assert_equal( 'Large', il2_rg.attrib['value'] )
    assert_equal( 'Medium,Tags', is_rg.attrib['value'] )
    assert_equal( 'Small,Reviews', is2_rg.attrib['value'] )

    # Check to see whether we can set the response group for all encapsulated
    # operations with a single assignment.
    #
    mo.response_group = ResponseGroup.new( :Small )
    response = @req.search( mo )
    mor = response.multi_operation_response[0]

    arguments = mor.operation_request.arguments.argument

    il_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.1.ResponseGroup'
    end[0]

    il2_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemLookup.2.ResponseGroup'
    end[0]

    is_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemSearch.1.ResponseGroup'
    end[0]

    is2_rg = arguments.select do |arg|
      arg.attrib['name'] == 'ItemSearch.2.ResponseGroup'
    end[0]

    assert_equal( 'Small', il_rg.attrib['value'] )
    assert_equal( 'Small', il2_rg.attrib['value'] )
    assert_equal( 'Small', is_rg.attrib['value'] )
    assert_equal( 'Small', is2_rg.attrib['value'] )

    # Ensure we received a MultiOperationResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::MultiOperationResponse, mor )
    
    # Ensure response contains an ItemSearchResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemSearchResponse,
		        mor.item_search_response[0] )

    # Ensure response also contains an ItemLookupResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemLookupResponse,
		        mor.item_lookup_response[0] )
 
    is_set = mor.item_search_response[0].items
    il_set = mor.item_lookup_response[0].items

    # Ensure that there are two <ItemSet>s for the ItemSearch.
    #
    assert_equal( 2, is_set.size )

    # Ensure that there are two <ItemSet>s for the ItemLookup.
    #
    assert_equal( 2, il_set.size )

    is_arr = is_set[0].item
    is2_arr = is_set[1].item
    il_arr = il_set[0].item
    il2_arr = il_set[1].item

    # Assure that all item sets have some results.
    #
    assert( is_arr.size > 0 )
    assert( is2_arr.size > 0 )
    assert( il_arr.size > 0 )
    assert( il2_arr.size > 0 )

    mo = MultipleOperation.new( [ is, il, bnl ] )
    assert_raise( Amazon::AWS::Error::ExceededMaxMultiOpOperations ) do
      @req.search( mo )
    end
  end


  def test_multiple_class_method
    il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC',
				   'MerchantId' => 'Amazon' } )
    il.response_group = ResponseGroup.new( :Large )

    is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
    is.response_group = ResponseGroup.new( :Medium, :Tags )

    response = Amazon::AWS.multiple_operation( is, il )
    mor = response.multi_operation_response[0]

    # Ensure we received a MultiOperationResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::MultiOperationResponse, mor )
    
    # Ensure response contains an ItemSearchResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemSearchResponse,
		        mor.item_search_response[0] )

    # Ensure response also contains an ItemLookupResponse.
    #
    assert_instance_of( Amazon::AWS::AWSObject::ItemLookupResponse,
		        mor.item_lookup_response[0] )
 
    is_set = response.multi_operation_response.item_search_response[0].items
    il_set = response.multi_operation_response.item_lookup_response[0].items
    is_arr = is_set.item
    il_arr = il_set[0].item

    # Ensure that there's one <ItemSet> for the ItemSearch.
    #
    assert_equal( 1, is_set.size )

    # Ensure that there's one <ItemSet> for the ItemLookup.
    #
    assert_equal( 1, il_set.size )

    # Assure that all item sets have some results.
    #
    assert( is_arr.size > 0 )
    assert( il_arr.size > 0 )
  end

end
