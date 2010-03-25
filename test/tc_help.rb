# $Id: tc_help.rb,v 1.3 2010/02/20 17:15:17 ianmacd Exp $
#

require 'test/unit'
require './setup'

class TestHelp < AWSTest

  def test_help

    h = Help.new( 'ResponseGroup', 'Large' )
    rg = ResponseGroup.new( 'Help' )
    h.response_group = rg
    response = @req.search( h )

    # Get a list of valid operations for the Large response group.
    #
    results = response.help_response[0].information.response_group_information.
	      valid_operations.operation

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

  def test_help_class_method

    response = Amazon::AWS.help( 'ResponseGroup', 'Large' )

    # With no response group, Large will be tried. The resulting exception
    # will be rescued and the text of the message returned by AWS will be used
    # to determine a response group that will work.
    #
    results = response.help_response[0].information.response_group_information.
	      valid_operations.operation

    # Ensure we got some actual results back.
    #
    assert( results.size > 0 )

  end

end
