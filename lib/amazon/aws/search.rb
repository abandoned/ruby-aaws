# $Id: search.rb,v 1.49 2010/03/19 19:28:19 ianmacd Exp $
#

module Amazon

  module AWS

    require 'amazon/aws'
    require 'net/http'
    require 'rexml/document'
    require 'openssl'

    # Load this library with:
    #
    #  require 'amazon/aws/search'
    #
    module Search

      class Request

	include REXML

	# Exception class for bad access key ID.
	#
	class AccessKeyIdError < Amazon::AWS::Error::AWSError; end

	# Exception class for bad locales.
	#
	class LocaleError < Amazon::AWS::Error::AWSError; end

	# Do we have support for the SHA-256 Secure Hash Algorithm?
	#
	# Note that Module#constants returns Strings in Ruby 1.8 and Symbols
	# in 1.9.
	#
	DIGEST_SUPPORT = OpenSSL::Digest.constants.include?( 'SHA256' ) ||
			 OpenSSL::Digest.constants.include?( :SHA256 )

	# Requests are authenticated using the SHA-256 Secure Hash Algorithm.
	#
	DIGEST = OpenSSL::Digest::Digest.new( 'sha256' ) if DIGEST_SUPPORT

	attr_reader :conn, :config, :locale, :query, :user_agent
	attr_writer :cache
	attr_accessor :encoding

	# This method is used to generate an AWS search request object.
	#
	# _key_id_ is your AWS {access key
	# ID}[https://aws-portal.amazon.com/gp/aws/developer/registration/index.html].
	# Note that your secret key, used for signing requests, can be
	# specified only in your <tt>~/.amazonrc</tt> configuration file.
	#
	# _associate_ is your
	# Associates[http://docs.amazonwebservices.com/AWSECommerceService/2009-11-01/GSG/BecominganAssociate.html]
	# tag (if any), _locale_ is the locale in which you which to work
	# (*us* for amazon.com[http://www.amazon.com/], *uk* for
	# amazon.co.uk[http://www.amazon.co.uk], etc.), _cache_ is whether or
	# not you wish to utilise a response cache, and _user_agent_ is the
	# client name to pass when performing calls to AWS. By default,
	# _user_agent_ will be set to a string identifying the Ruby/AWS
	# library and its version number.
	#
	# _locale_ and _cache_ can also be set later, if you wish to change
	# the current behaviour.
	#
	# Example:
	#
	#  req = Request.new( '0Y44V8FAFNM119CX4TR2', 'calibanorg-20' )
	#
	def initialize(key_id=nil, associate=nil, locale=nil, cache=nil,
		       user_agent=USER_AGENT)

	  @config ||= Amazon::Config.new

	  def_locale = locale
	  locale = 'us' unless locale
	  locale.downcase!

	  key_id ||= @config['key_id']
	  cache = @config['cache'] if cache.nil?

	  # Take locale from config file if no locale was passed to method.
	  #
	  if @config.key?( 'locale' ) && ! def_locale
	    locale = @config['locale']
	  end
	  validate_locale( locale )

	  if key_id.nil?
	    raise AccessKeyIdError, 'key_id may not be nil'
	  end

	  @key_id     = key_id
	  @tag	      = associate || @config['associate'] || DEF_ASSOC[locale]
	  @user_agent = user_agent
	  @cache      = unless cache == 'false' || cache == false
			  Amazon::AWS::Cache.new( @config['cache_dir'] )
			else
			  nil
			end

	  # Set the following two variables from the config file. Will be
	  # *nil* if not present in config file.
	  #
	  @api	      = @config['api']
	  @encoding   = @config['encoding']

	  self.locale = locale
	end


	# Assign a new locale. If the locale we're coming from is using the
	# default Associate ID for that locale, then we use the new locale's
	# default ID, too.
	#
	def locale=(l)  # :nodoc:
	  old_locale = @locale ||= nil
	  @locale = validate_locale( l )

	  # Use the new locale's default ID if the ID currently in use is the
	  # current locale's default ID.
	  #
	  if @tag == Amazon::AWS::DEF_ASSOC[old_locale]
	    @tag = Amazon::AWS::DEF_ASSOC[@locale]
	  end

	  if @config.key?( @locale ) && @config[@locale].key?( 'associate' )
	    @tag = @config[@locale]['associate']
	  end

	  # We must now set up a new HTTP connection to the correct server for
	  # this locale, unless the same server is used for both.
	  #
	  unless Amazon::AWS::ENDPOINT[@locale] ==
		 Amazon::AWS::ENDPOINT[old_locale]
	    #connect( @locale )
	    @conn = nil
	  end
	end


	# If @cache has simply been assigned *true* at some point in time,
	# assign a proper cache object to it when it is referenced. Otherwise,
	# just return its value.
	#
	def cache  # :nodoc:
	  if @cache == true
	    @cache = Amazon::AWS::Cache.new( @config['cache_dir'] )
	  else
	    @cache
	  end
	end


	# Verify the validity of a locale string. _l_ is the locale string.
	#
	def validate_locale(l)
	  unless Amazon::AWS::ENDPOINT.has_key? l
	    raise LocaleError, "invalid locale: #{l}"
	  end
	  l
	end
	private :validate_locale


	# Return an HTTP connection for the current _locale_.
	#
	def connect(locale)
	  if ENV.key? 'http_proxy'
	    uri = URI.parse( ENV['http_proxy'] )
	    proxy_user = proxy_pass = nil
	    proxy_user, proxy_pass = uri.userinfo.split( /:/ ) if uri.userinfo
	    @conn = Net::HTTP::Proxy( uri.host, uri.port, proxy_user,
				      proxy_pass ).start(
					Amazon::AWS::ENDPOINT[locale].host )
	  else
	    @conn = Net::HTTP::start( Amazon::AWS::ENDPOINT[locale].host )
	  end
	end
	private :connect


	# Reconnect to the server if our connection has been lost (due to a
	# time-out, etc.).
	#
	def reconnect  # :nodoc:
	  connect( self.locale )
	  self
	end


	# This method checks for errors in an XML response returned by AWS.
	# _xml_ is the XML node below which to search.
	#
	def error_check(xml)
	  if ! xml.nil? && xml = xml.elements['Errors/Error']
	    raise Amazon::AWS::Error.exception( xml )
	  end
	end
	private :error_check


	# Add a timestamp to a request object's query string.
	#
	def timestamp # :nodoc:
	  @query << '&Timestamp=%s' %
	    [ Amazon.url_encode(
		Time.now.utc.strftime( '%Y-%m-%dT%H:%M:%SZ' ) ) ]
	end
	private :timestamp


	# Add a signature to a request object's query string. This implicitly
	# also adds a timestamp.
	#
	def sign # :nodoc:
	  return false unless DIGEST_SUPPORT

	  timestamp
	  params = @query[1..-1].split( '&' ).sort.join( '&' )
  
	  sign_str = "GET\n%s\n%s\n%s" % [ ENDPOINT[@locale].host,
					   ENDPOINT[@locale].path,
					   params ]

	  Amazon.dprintf( 'Calculating SHA256 HMAC of "%s"...', sign_str )

	  hmac = OpenSSL::HMAC.digest( DIGEST,
				       @config['secret_key_id'],
				       sign_str )
	  Amazon.dprintf( 'SHA256 HMAC is "%s"', hmac.inspect )

	  base64_hmac = [ hmac ].pack( 'm' ).chomp
	  Amazon.dprintf( 'Base64-encoded HMAC is "%s".', base64_hmac )

	  signature = Amazon.url_encode( base64_hmac )

	  params << '&Signature=%s' % [ signature ]
	  @query = '?' + params

	  true
	end


	# Perform a search of the AWS database, returning an AWSObject.
	#
	# _operation_ is an object of a subclass of _Operation_, such as
	# _ItemSearch_, _ItemLookup_, etc. It may also be a _MultipleOperation_
	# object.
	#
	# In versions of Ruby/AWS up to prior to 0.8.0, the second parameter to
	# this method was _response_group_. This way of passing response
	# groups has been deprecated since 0.7.0 and completely removed in
	# 0.8.0. To pair a set of response groups with an operation, assign
	# directly to the operation's @response_group attribute.
	#
	# _nr_pages_ is the number of results pages to return. It defaults to
	# <b>1</b>. If a higher number is given, pages 1 to _nr_pages_ will be
	# returned. If the special value <b>:ALL_PAGES</b> is given, all
	# results pages will be returned.
	#
	# Note that _ItemLookup_ operations can use several different
	# pagination parameters. An _ItemLookup_ will typically return just
	# one results page containing a single product, but <b>:ALL_PAGES</b>
	# can still be used to apply the _OfferPage_ parameter to paginate
	# through multiple pages of offers.
	#
	# Similarly, a single product may have multiple pages of reviews
	# available. In such a case, it is up to the user to manually supply
	# the _ReviewPage_ parameter and an appropriate value.
	#
	# In the same vein, variations can be returned by using the
	# _VariationPage_ parameter.
	#
	# The pagination parameters supported by each type of operation,
	# together with the maximum page number that can be retrieved for each
	# type of data, are # documented in the AWS Developer's Guide:
	#
	# http://docs.amazonwebservices.com/AWSECommerceService/2009-11-01/DG/index.html?MaximumNumberofPages.html
	#
	# The pagination parameter used by <b>:ALL_PAGES</b> can be looked up
	# in the Amazon::AWS::PAGINATION hash.
	#
	# If _operation_ is of class _MultipleOperation_, the operations
	# encapsulated within will return only the first page of results,
	# regardless of whether a higher number of pages is requested.
	#
	# If a block is passed to this method, each successive page of results
	# will be yielded to the block.
	#
	def search(operation, nr_pages=1)
	  parameters = Amazon::AWS::SERVICE.
			 merge( { 'AWSAccessKeyId' => @key_id,
				  'AssociateTag'   => @tag } ).
			 merge( operation.query_parameters )

	  if nr_pages.is_a? Amazon::AWS::ResponseGroup
	    raise ObsolescenceError, 'Request#search method no longer accepts response_group parameter.'
	  end

	  # Pre-0.8.0 user code may have passed *nil* as the second parameter,
	  # in order to use the @response_group of the operation.
	  #
	  nr_pages ||= 1

	  # Check to see whether a particular version of the API has been
	  # requested. If so, overwrite Version with the new value.
	  #
	  parameters.merge!( { 'Version' => @api } ) if @api

	  @query = Amazon::AWS.assemble_query( parameters, @encoding )
	  page = Amazon::AWS.get_page( self )

	  # Ruby 1.9 needs to know that the page is UTF-8, not ASCII-8BIT.
	  #
	  page.force_encoding( 'utf-8' ) if RUBY_VERSION >= '1.9.0'

	  doc = Document.new( page )

	  # Some errors occur at the very top level of the XML. For example,
	  # when no Operation parameter is given. This should not be possible
	  # with user code, but occurred during debugging of this library.
	  #
	  error_check( doc )

	  # Another possible error results in a document containing nothing
	  # but <Result>Internal Error</Result>. This occurs when a specific
	  # version of the AWS API is requested, in combination with an
	  # operation that did not yet exist in that version of the API.
	  #
	  # For example:
	  #
	  # http://ecs.amazonaws.com/onca/xml?AWSAccessKeyId=foo&Operation=VehicleSearch&Year=2008&ResponseGroup=VehicleMakes&Service=AWSECommerceService&Version=2008-03-03
	  #
	  if xml = doc.elements['Result']
	    raise Amazon::AWS::Error::AWSError, xml.text
	  end

	  # Fundamental errors happen at the OperationRequest level. For
	  # example, if an invalid AWSAccessKeyId is used.
	  #
	  error_check( doc.elements['*/OperationRequest'] )

	  # Check for parameter and value errors deeper down, inside Request.
	  #
	  if operation.kind == 'MultipleOperation'

	    # Everything is a level deeper, because of the
	    # <MultiOperationResponse> container.
	    #
	    # Check for errors in the first operation.
	    #
	    error_check( doc.elements['*/*/*/Request'] )

	    # Check for errors in the second operation.
	    #
	    error_check( doc.elements['*/*[3]/*/Request'] )

	    # If second operation is batched, check for errors in its 2nd set
	    # of results.
	    #
	    if batched = doc.elements['*/*[3]/*[2]/Request']
	      error_check( batched )
	    end
	  else
	    error_check( doc.elements['*/*/Request'] )

	    # If operation is batched, check for errors in its 2nd set of
	    # results.
	    #
	    if batched = doc.elements['*/*[3]/Request']
	      error_check( batched )
	    end
	  end

	  if doc.elements['*/*[2]/TotalPages']
	    total_pages = doc.elements['*/*[2]/TotalPages'].text.to_i

	  # FIXME: ListLookup and MultipleOperation (and possibly others) have
	  # TotalPages nested one level deeper. I should take some time to
	  # ensure that all operations that can return multiple results pages
	  # are covered by either the 'if' above or the 'elsif' here.
	  #
	  elsif doc.elements['*/*[2]/*[2]/TotalPages']
	    total_pages = doc.elements['*/*[2]/*[2]/TotalPages'].text.to_i
	  else
	    total_pages = 1
	  end

	  # Create a root AWS object and walk the XML response tree.
	  #
	  aws = AWS::AWSObject.new( operation )
	  aws.walk( doc )
	  result = aws

	  # If only one page has been requested or only one page is available,
	  # we can stop here. First yield to the block, if given.
	  #
	  if nr_pages == 1 || ( tp = total_pages ) == 1
	     yield result if block_given?
	     return result
	  end

	  # Limit the number of pages to the maximum number available.
	  #
	  nr_pages = tp.to_i if nr_pages == :ALL_PAGES || nr_pages > tp.to_i

	  if PAGINATION.key? operation.kind
	    page_parameter = PAGINATION[operation.kind]['parameter']
	    max_pages = PAGINATION[operation.kind]['max_page']
	  else
	    page_parameter = 'ItemPage'
	    max_pages = 400
	  end

	  # Iterate over pages 2 and higher, but go no higher than MAX_PAGES.
	  #
	  2.upto( nr_pages < max_pages ? nr_pages : max_pages ) do |page_nr|
	    @query = Amazon::AWS.assemble_query(
		      parameters.merge( { page_parameter => page_nr } ),
		      @encoding)
	    page = Amazon::AWS.get_page( self )

	    # Ruby 1.9 needs to know that the page is UTF-8, not ASCII-8BIT.
	    #
	    page.force_encoding( 'utf-8' ) if RUBY_VERSION >= '1.9.0'

	    doc = Document.new( page )

	    # Check for errors.
	    #
	    error_check( doc.elements['*/OperationRequest'] )
	    error_check( doc.elements['*/*/Request'] )

	    # Create a new AWS object and walk the XML response tree.
	    #
	    aws = AWS::AWSObject.new( operation )
	    aws.walk( doc )

	    # When dealing with multiple pages, we return not just an
	    # AWSObject, but an array of them.
	    #
	    result = [ result ] unless result.is_a? Array

	    # Append the new object to the array.
	    #
	    result << aws
	  end

	  # Yield each object to the block, if given.
	  #
	  result.each { |r| yield r } if block_given?

	  result
	end

      end

    end

  end

end
