# $Id: aws.rb,v 1.130 2010/03/20 11:58:50 ianmacd Exp $
#
#:include: ../../README.rdoc

module Amazon

  module AWS

    require 'amazon'
    require 'amazon/aws/cache'
    require 'enumerator'
    require 'iconv'
    require 'rexml/document'
    require 'uri'

    NAME = '%s/%s' % [ Amazon::NAME, 'AWS' ]
    VERSION = '0.8.1'
    USER_AGENT = '%s %s' % [ NAME, VERSION ]

    # Default Associate tags to use per locale.
    #
    DEF_ASSOC  = {
      'ca' => 'caliban-20',
      'de' => 'calibanorg0a-21',
      'fr' => 'caliban08-21',
      'jp' => 'calibanorg-20',
      'uk' => 'caliban-21',
      'us' => 'calibanorg-20'
    }

    # Service name and API version for AWS. The version of the API used can be
    # changed via the user configuration file.
    #
    SERVICE = { 'Service' => 'AWSECommerceService',
		'Version' => '2009-11-01'
    }

    # Maximum number of 301 and 302 HTTP responses to follow, should Amazon
    # later decide to change the location of the service.
    #
    MAX_REDIRECTS = 3

    # Maximum number of results pages that can be retrieved for a given
    # search operation, using whichever pagination parameter is appropriate
    # for that kind of operation.
    #
    PAGINATION = {
      'ItemSearch'	      => { 'parameter' => 'ItemPage',
						  'max_page' => 400 },
      'ItemLookup'	      => { 'parameter' => 'OfferPage',
						  'max_page' => 100 },
      'ListLookup'	      => { 'parameter' => 'ProductPage',
						  'max_page' =>  30 },
      'ListSearch'	      => { 'parameter' => 'ListPage',
						  'max_page' =>  20 },
      'CustomerContentLookup' => { 'parameter' => 'ReviewPage',
						  'max_page' =>  10 },
      'CustomerContentSearch' => { 'parameter' => 'CustomerPage',
						  'max_page' =>  20 },
      'VehiclePartLookup'     => { 'parameter' => 'FitmentPage',
						  'max_page' =>  10 }
    }
    # N.B. ItemLookup can also use the following two pagination parameters
    #
    #		      max. page
    #		      ---------
    # VariationPage   150
    # ReviewPage       20
  

    # A hash to store character encoding converters.
    #
    @@encodings = {}


    # Exception class for HTTP errors.
    #
    class HTTPError < AmazonError; end


    # Exception class for faulty batch operations.
    #
    class BatchError < AmazonError; end


    # Exception class for obsolete features.
    #
    class ObsolescenceError < AmazonError; end


    class Endpoint

      attr_reader :host, :path

      def initialize(endpoint)
	uri = URI.parse( endpoint )
	@host = uri.host
	@path = uri.path
      end
    end

    ENDPOINT = {
      'ca' => Endpoint.new( 'http://ecs.amazonaws.ca/onca/xml' ),
      'de' => Endpoint.new( 'http://ecs.amazonaws.de/onca/xml' ),
      'fr' => Endpoint.new( 'http://ecs.amazonaws.fr/onca/xml' ),
      'jp' => Endpoint.new( 'http://ecs.amazonaws.jp/onca/xml' ),
      'uk' => Endpoint.new( 'http://ecs.amazonaws.co.uk/onca/xml' ),
      'us' => Endpoint.new( 'http://ecs.amazonaws.com/onca/xml' )
    }


    # Fetch a page, either from the cache or by HTTP. This is used internally.
    #
    def AWS.get_page(request)  # :nodoc:

      url = ENDPOINT[request.locale].path + request.query
      cache_url = ENDPOINT[request.locale].host + url

      # Check for cached page and return that if it's there.
      #
      if request.cache && request.cache.cached?( cache_url )
	body = request.cache.fetch( cache_url )
	return body if body
      end

      # Check whether we have a secret key available for signing the request.
      # If so, sign the request for authentication.
      #
      if request.config['secret_key_id']
	unless request.sign
	  Amazon.dprintf( 'Warning! Failed to sign request. No OpenSSL support for SHA256 digest.' )
	end

	url = ENDPOINT[request.locale].path + request.query
      end

      # Get the existing connection. If there isn't one, force a new one.
      #
      conn = request.conn || request.reconnect.conn
      user_agent = request.user_agent

      Amazon.dprintf( 'Fetching http://%s%s ...', conn.address, url )

      begin
	response = conn.get( url, { 'user-agent' => user_agent } )

      # If we've pulled and processed a lot of pages from the cache (or
      # just not passed by here recently), the HTTP connection to the server
      # will probably have timed out.
      #
      rescue EOFError,		Errno::ECONNABORTED, Errno::ECONNREFUSED,
	     Errno::ECONNRESET, Errno::EPIPE,	     Errno::ETIMEDOUT,
	     Timeout::Error	=> error
	Amazon.dprintf( 'Connection to server lost: %s. Retrying...', error )
	conn = request.reconnect.conn
	retry
      end

      redirects = 0
      while response.key? 'location'
	if ( redirects += 1 ) > MAX_REDIRECTS
	  raise HTTPError, "More than #{MAX_REDIRECTS} redirections"
	end

	old_url = url
	url = URI.parse( response['location'] )
	url.scheme = old_url.scheme unless url.scheme
	url.host = old_url.host unless url.host
	Amazon.dprintf( 'Following HTTP %s to %s ...', response.code, url )
	response = Net::HTTP::start( url.host ).
		     get( url.path, { 'user-agent' => user_agent } )
      end

      if response.code != '200'
	raise HTTPError, "HTTP response code #{response.code}"
      end

      # Cache the page if we're using a cache.
      #
      if request.cache
	request.cache.store( cache_url, response.body )
      end

      response.body
    end


    def AWS.assemble_query(items, encoding=nil)  # :nodoc:

      query = ''
      @@encodings[encoding] ||= Iconv.new( 'utf-8', encoding ) if encoding

      # We must sort the items into an array to get reproducible ordering
      # of the query parameters. Otherwise, URL caching would not work. We
      # must also convert the parameter values to strings, in case Symbols
      # have been used as the values.
      #
      items.sort { |a,b| a.to_s <=> b.to_s }.each do |k, v|
	if encoding
	  query << '&%s=%s' %
	    [ k, Amazon.url_encode( @@encodings[encoding].iconv( v.to_s ) ) ]
	else
	  query << '&%s=%s' % [ k, Amazon.url_encode( v.to_s ) ]
	end
      end

      # Replace initial ampersand with question-mark.
      #
      query[0] = '?'

      query
    end


    # Everything returned by AWS is an AWSObject.
    #
    class AWSObject

      include REXML

      # This method can be used to load AWSObject data previously serialised
      # by Marshal.dump.
      #
      # Example:
      #
      #  File.open( 'aws.dat' ) { |f| Amazon::AWS::AWSObject.load( f ) }
      #
      # Marshal.load cannot be used directly, because subclasses of AWSObject
      # are dynamically defined as needed when AWS XML responses are parsed.
      #
      # Later attempts to load objects instantiated from these classes cause a
      # problem for Marshal, because it knows nothing of classes that were
      # dynamically defined by a separate process.
      #
      def AWSObject.load(io)
	begin
	  Marshal.load( io )
	rescue ArgumentError => ex
	  m = ex.to_s.match( /Amazon::AWS::AWSObject::([^ ]+)/ )
	  const_set( m[1], Class.new( AWSObject ) )

	  io.rewind
	  retry
	end
      end
 

      # This method can be used to load AWSObject data previously serialised
      # by YAML.dump.
      #
      # Example:
      #
      #  File.open( 'aws.yaml' ) { |f| Amazon::AWS::AWSObject.yaml_load( f ) }
      #
      # The standard YAML.load cannot be used directly, because subclasses of
      # AWSObject are dynamically defined as needed when AWS XML responses are
      # parsed.
      #
      # Later attempts to load objects instantiated from these classes cause a
      # problem for YAML, because it knows nothing of classes that were
      # dynamically defined by a separate process.
      #
      def AWSObject.yaml_load(io)
	io.each do |line|
    
	  # File data is external, so it's deemed unsafe when $SAFE > 0, which
	  # is the case with mod_ruby, for example, where $SAFE == 1.
	  #
	  # YAML data isn't eval'ed or anything dangerous like that, so we
	  # consider it safe to untaint it. If we don't, mod_ruby will complain
	  # when Module#const_defined? is invoked a few lines down from here.
	  #
	  line.untaint
	  
	  m = line.match( /Amazon::AWS::AWSObject::([^ ]+)/ )
	  if m
	    cl_name = [ m[1] ]
	  
	    # Module#const_defined? takes 2 parameters in Ruby 1.9.
	    #
	    cl_name << false if RUBY_VERSION >= '1.9.0'
	  
	    unless AWSObject.const_defined?( *cl_name )
	      AWSObject.const_set( m[1], Class.new( AWSObject ) )
	    end
	  
	  end
	end
    
	io.rewind
	YAML.load( io )
      end


      def initialize(op=nil)
	# The name of this instance variable must never clash with the
	# uncamelised name of an Amazon tag.
	#
	# This is used to store the REXML::Text value of an element, which
	# exists only when the element contains no children.
	#
	@__val__ = nil
	@__op__ = op if op
      end


      def method_missing(method, *params)
	iv = '@' + method.id2name

	if instance_variables.include?( iv )

	  # Return the instance variable that matches the method called.
	  #
	  instance_variable_get( iv )
	elsif instance_variables.include?( iv.to_sym )

	  # Ruby 1.9 Object#instance_variables method returns Array of Symbol,
	  # not String.
	  #
	  instance_variable_get( iv.to_sym )
	elsif @__val__.respond_to?( method.id2name )

	  # If our value responds to the method in question, call the method
	  # on that.
	  #
	  @__val__.send( method.id2name )
	else
	  nil
	end
      end
      private :method_missing
 

      def remove_val
	remove_instance_variable( :@__val__ )
      end
      private :remove_val


      # Iterator method for cycling through an object's properties and values.
      #
      def each  # :yields: property, value
	self.properties.each do |iv|
	  yield iv, instance_variable_get( "@#{iv}" )
	end
      end

      alias :each_property :each


      def inspect  # :nodoc:
	remove_val if instance_variable_defined?( :@__val__ ) && @__val__.nil?
	str = super
	str.sub( /@__val__=/, 'value=' ) if str
      end


      def to_s	# :nodoc:
	if instance_variable_defined?( :@__val__ )
	  return @__val__ if @__val__.is_a?( String )
	  remove_val
	end

	string = ''

	# Assemble the object's details.
	#
	each { |iv, value| string << "%s = %s\n" % [ iv, value ] }

	string
      end

      alias :to_str :to_s


      def ==(other)  # :nodoc:
	@__val__.to_s == other
      end


      def =~(other)  # :nodoc:
	@__val__.to_s =~ other
      end


      # This alias makes the ability to determine an AWSObject's properties a
      # little more intuitive. It's pretty much just an alias for the
      # inherited <em>Object#instance_variables</em> method, with a little
      # tidying.
      #
      def properties
	# Make sure we remove the leading @.
	#
	iv = instance_variables.collect { |v| v = v[1..-1] }
	iv.delete( '__val__' )
	iv
      end


      # Provide a shortcut down to the data likely to be of most interest.
      # This method is experimental and may be removed.
      #
      def kernel  # :nodoc: 
	# E.g. Amazon::AWS::SellerListingLookup -> seller_listing_lookup
	#
	stub = Amazon.uncamelise( @__op__.class.to_s.sub( /^.+::/, '' ) )

	# E.g. seller_listing_response
	#
	level1 = stub + '_response'

	# E.g. seller_listing
	#
	level3 = stub.sub( /_[^_]+$/, '' )

	# E.g. seller_listings
	#
	level2 = level3 + 's'

	# E.g.
	# seller_listing_search_response[0].seller_listings[0].seller_listing
	#
	self.instance_variable_get( "@#{level1}" )[0].
	     instance_variable_get( "@#{level2}" )[0].
	     instance_variable_get( "@#{level3}" )
      end


      # Convert an AWSObject to a Hash.
      #
      def to_h
	hash = {}

	each do |iv, value|
	  if value.is_a? AWSObject
	    hash[iv] = value.to_h
	  elsif value.is_a?( AWSArray ) && value.size == 1
	    hash[iv] = value[0]
	  else
	    hash[iv] = value
	  end
	end

	hash
      end


      # Fake the appearance of an AWSObject as a hash. _key_ should be any
      # attribute of the object and can be a String, Symbol or anything else
      # that can be converted to a String with to_s.
      #
      def [](key)
	instance_variable_get( "@#{key}" )
      end


      # Recursively walk through an XML tree, starting from _node_. This is
      # called internally and is not intended for user code.
      #
      def walk(node)  # :nodoc:
    
	if node.instance_of?( REXML::Document )
	  walk( node.root )
    
	elsif node.instance_of?( REXML::Element )
	  name = Amazon.uncamelise( node.name )
    
	  cl_name = [ node.name ]

	  # Module#const_defined? takes 2 parameters in Ruby 1.9.
	  #
	  cl_name << false if RUBY_VERSION >= '1.9.0'

	  # Create a class for the new element type unless it already exists.
	  #
	  unless AWS::AWSObject.const_defined?( *cl_name )
	    cl = AWS::AWSObject.const_set( node.name, Class.new( AWSObject ) )

	    # Give it an accessor for @attrib.
	    #
	    cl.send( :attr_accessor, :attrib )
	  end
    
	  # Instantiate an object in the newly created class.
	  #
	  obj = AWS::AWSObject.const_get( node.name ).new

	  sym_name = "@#{name}".to_sym
    
	  if instance_variable_defined?( sym_name)
    	    instance_variable_set( sym_name,
    	      instance_variable_get( sym_name ) << obj )
	  else
	    instance_variable_set( sym_name, AWSArray.new( [ obj ] ) )
	  end
    
	  if node.has_attributes?
	    obj.attrib = {}
	    node.attributes.each_pair do |a_name, a_value|
	      obj.attrib[a_name.downcase] =
		a_value.to_s.sub( /^#{a_name}=/, '' )
	    end
	  end

	  node.children.each { |child| obj.walk( child ) }
    
	else # REXML::Text
	  @__val__ = node.to_s
	end
      end


      # For objects of class AWSObject::.*Image, fetch the image in question,
      # optionally overlaying a discount icon for the percentage amount of
      # _discount_ to the image.
      #
      def get(discount=nil)
	if self.class.to_s =~ /Image$/ && @url
	  url = URI.parse( @url[0] )
	  url.path.sub!( /(\.\d\d\._)/, "\\1PE#{discount}" ) if discount

	  # FIXME: All HTTP in Ruby/AWS should go through the same method.
	  #
	  Net::HTTP.start( url.host, url.port ) do |http|
	    http.get( url.path )
	  end.body

	else
	  nil
	end
      end

    end


    # Everything we get back from AWS is transformed into an array. Many of
    # these, however, have only one element, because the corresponding XML
    # consists of a parent element containing only a single child element.
    #
    # This class consists solely to allow single element arrays to pass a
    # method call down to their one element, thus obviating the need for lots
    # of references to <tt>foo[0]</tt> in user code.
    #
    # For example, the following:
    #
    #  items = resp.item_search_response[0].items[0].item
    #
    # can be reduced to:
    #
    #  items = resp.item_search_response.items.item
    #
    class AWSArray < Array

      def method_missing(method, *params)
	self.size == 1 ? self[0].send( method, *params ) : super
      end
      private :method_missing


      # In the case of a single-element array, return the first element,
      # converted to a String.
      #
      def to_s  # :nodoc:
	self.size == 1 ? self[0].to_s : super
      end

      alias :to_str :to_s


      # In the case of a single-element array, return the first element,
      # converted to an Integer.
      #
      def to_i  # :nodoc:
	self.size == 1 ? self[0].to_i : super
      end


      # In the case of a single-element array, compare the first element with
      # _other_.
      #
      def ==(other)  # :nodoc:
	self.size == 1 ? self[0].to_s == other : super
      end


      # In the case of a single-element array, perform a pattern match on the
      # first element against _other_.
      #
      def =~(other)  # :nodoc:
	self.size == 1 ? self[0].to_s =~ other : super
      end

    end

 
    # This is the base class of all AWS operations.
    #
    class Operation

      # These are the types of AWS operation currently implemented by Ruby/AWS.
      #
      OPERATIONS = %w[
	BrowseNodeLookup      CustomerContentLookup   CustomerContentSearch
	Help		      ItemLookup	      ItemSearch
	ListLookup	      ListSearch	      MultipleOperation
	SellerListingLookup   SellerListingSearch     SellerLookup
	SimilarityLookup      TagLookup		      TransactionLookup
	VehiclePartLookup     VehiclePartSearch	      VehicleSearch

	CartAdd		      CartClear		      CartCreate
	CartGet		      CartModify
      ]

      attr_reader :kind
      attr_accessor :params, :response_group

      def initialize(parameters)

	op_kind = self.class.to_s.sub( /^.*::/, '' )

	raise "Bad operation: #{op_kind}" unless OPERATIONS.include?( op_kind )

	if ResponseGroup::DEFAULT.key?( op_kind )
	  response_group =
	    ResponseGroup.new( ResponseGroup::DEFAULT[op_kind] )
	else
	  response_group = nil
	end

	if op_kind =~ /^Cart/
	  @params = parameters
	else
	  @params = Hash.new { |hash, key| hash[key] = [] }
	  @response_group = Hash.new { |hash, key| hash[key] = [] }

	  unless op_kind == 'MultipleOperation'
	    @params[op_kind] = [ parameters ]
	    @response_group[op_kind] = [ response_group ]
	  end
	end

	@kind = op_kind
      end


      # Make sure we can still get to the old @response_group= writer method.
      #
      alias :response_group_orig= :response_group=

      # If the user assigns to @response_group, we need to set this response
      # group for any and all operations that may have been batched.
      #
      def response_group=(rg) # :nodoc:
        @params.each_value do |op_arr|
          op_arr.each do |op|
            op['ResponseGroup'] = rg
          end
        end
      end


      # Group together operations of the same class in a batch request.
      # _operations_ should be either an operation of the same class as *self*
      # or an array of such operations.
      #
      # If you need to batch operations of different classes, use a
      # MultipleOperation instead.
      #
      # Example:
      #
      #  is = ItemSearch.new( 'Books', { 'Title' => 'ruby programming' } )
      #  is2 = ItemSearch.new( 'Music', { 'Artist' => 'stranglers' } )
      #  is.response_group = ResponseGroup.new( :Small )
      #  is2.response_group = ResponseGroup.new( :Tracks )
      #  is.batch( is2 )
      #
      # Please see MultipleOperation.new for implementation details that also
      # apply to batched operations.
      #
      def batch(*operations)

	operations.flatten.each do |op|

	  unless self.class == op.class
	    raise BatchError, "You can't batch operations of different classes. Use class MultipleOperation."
	  end

	  # Add the operation's single element array containing the parameter
	  # hash to the array.
	  #
	  @params[op.kind].concat( op.params[op.kind] )

	  # Add the operation's response group array to the array.
	  #
	  @response_group[op.kind].concat( op.response_group[op.kind] )
	end

      end


      # Return a hash of operation parameters and values, possibly converted to
      # batch syntax, suitable for encoding in a query.
      #
      def query_parameters  # :nodoc:
        query = {}

        @params.each do |op_kind, ops|

          # If we have only one type of operation and only one operation of
	  # that type, return that one in non-batched syntax.
          #
          if @params.size == 1 && @params[op_kind].size == 1
            return { 'Operation' => op_kind,
          	   'ResponseGroup' => @response_group[op_kind][0] }.
          	   merge( @params[op_kind][0] )
          end

          # Otherwise, use batch syntax.
          #
          ops.each_with_index do |op, op_index|

            # Make sure we use a response group of some kind.
            #
            shared = '%s.%d.ResponseGroup' % [ op_kind, op_index + 1 ]
            query[shared] = op['ResponseGroup'] ||
          		  ResponseGroup::DEFAULT[op_kind]

            # Add all of the parameters to the query hash.
            #
            op.each do |k, v|
              shared = '%s.%d.%s' % [ op_kind, op_index + 1, k ]
              query[shared] = v
            end
          end
        end

        # Add the operation list.
        #
        { 'Operation' => @params.keys.join( ',' ) }.merge( query )
      end

    end


    # This class can be used to encapsulate multiple operations in a single
    # operation for greater efficiency.
    #
    class MultipleOperation < Operation

      # This allows you to take multiple Operation objects and encapsulate them
      # to form a single object, which can then be used to send a single
      # request to AWS. This allows for greater efficiency, reducing the number
      # of requests sent to AWS.
      #
      # AWS currently imposes a limit of two operations when encapsulating
      # operations in a multiple operation. Note, however, that one or both of
      # these operations may be a batched operation. Combining two batched
      # operations in this way makes it possible to send as many as four
      # simple operations to AWS in a single MultipleOperation request.
      #
      # _operations_ is an array of objects subclassed from Operation, such as
      # ItemSearch, ItemLookup, etc.
      #
      # Please note the following implementation details:
      #
      # - As mentioned above, Amazon currently imposes a limit of two
      #   operations encapsulated in a MultipleOperation.
      #
      # - To use a different set of response groups for each encapsulated
      #   operation, assign to each operation's @response_group attribute prior
      #   to encapulation in a MultipleOperation.
      #
      # - To use the same set of response groups for all encapsulated
      #   operations, you can directly assign to the @response_group attribute
      #   of the MultipleOperation. This will propagate to the encapsulated
      #   operations.
      #
      # - One or both operations may have multiple results pages available,
      #   but only the first page will be returned by your requests. If you
      #   need subsequent pages, you must perform the operations separately.
      #   It is not possible to page through the results of a MultipleOperation
      #   response.
      #
      # - In this implementation, an error in any of the constituent operations
      #   will cause an exception to be thrown. If you don't want partial
      #   success (i.e. the success of fewer than all of the operations) to be
      #   treated as failure, you should perform the operations separately.
      #
      # - MultipleOperation is intended for encapsulation of objects from
      #   different classes, e.g. an ItemSearch and an ItemLookup. If you just
      #   want to batch operations of the same class, Operation#batch
      #   provides an alternative.
      #
      #   In fact, if you create a MultipleOperation encapsulating objects of
      #   the same class, Ruby/AWS will actually apply simple batch syntax to
      #   your request, so it amounts to the same as using Operation#batch.
      #
      # - Although all of the encapsulated operations can be batched
      #   operations, Amazon places a limit of two on the number of same-class
      #   operations that can be carried out in any one request. This means
      #   that you cannot encapsulate two batched requests from the same
      #   class, so attempting, for example, four ItemLookup operations via
      #   two batched ItemLookup operations will not work.
      #
      # Example:
      #
      #  is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
      #  il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B0013DZAYO',
      #					'MerchantId' => 'Amazon' } )
      #  is.response_group = ResponseGroup.new( :Large )
      #  il.response_group = ResponseGroup.new( :Small )
      #  mo = MultipleOperation.new( is, il )
      # 
      def initialize(*operations)

	# Start with an empty parameter hash.
	#
	super( {} )
	
	# Start off with the first operation and duplicate the original's
	# parameters to avoid accidental in-place modification.
	#
	operations.flatten!
	@params = operations.shift.params.freeze.dup

	# Add subsequent operations' parameter hashes, protecting them
	# against accidental in-place modification.
	#
	operations.each do |op|
	  op.params.freeze.each do |op_kind, op_arr|
	    @params[op_kind].concat( op_arr )
	  end
	end

      end
      
    end


    # This class of operation aids in finding out about AWS operations and
    # response groups.
    #
    class Help < Operation

      # Return information on AWS operations and response groups.
      #
      # For operations, required and optional parameters are returned, along
      # with information about which response groups the operation can use.
      #
      # For response groups, The list of operations that can use that group is
      # returned, as well as the list of response tags returned by the group.
      #
      # _help_type_ is the type of object for which help is being sought, such
      # as *Operation* or *ResponseGroup*. _about_ is the name of the
      # operation or response group you need help with, and _parameters_ is an
      # optional hash of parameters that further refine the request for help.
      #
      def initialize(help_type, about, parameters={})
	super( { 'HelpType' => help_type,
		 'About'    => about
	       }.merge( parameters ) )
      end

    end


    # This is the class for the most common type of AWS look-up, an
    # ItemSearch. This allows you to search for items that match a set of
    # broad criteria. It returns items for sale by Amazon merchants and most
    # types of seller.
    #
    class ItemSearch < Operation

      # Not all search indices work in all locales. It is the user's
      # responsibility to ensure that a given index is valid within a given
      # locale.
      #
      # According to the AWS documentation:
      #
      # - *All* searches through all indices.
      # - *Blended* combines Apparel, Automotive, Books, DVD, Electronics,
      #   GourmetFood, Kitchen, Music, PCHardware, PetSupplies, Software,
      #   SoftwareVideoGames, SportingGoods, Tools, Toys, VHS and VideoGames.
      # - *Merchants* combines all search indices for a merchant given with
      #   MerchantId.
      # - *Music* combines the Classical, DigitalMusic, and MusicTracks
      #   indices.
      # - *Video* combines the DVD and VHS search indices.
      #
      SEARCH_INDICES = %w[
	All
	Apparel
	Automotive
	Baby
	Beauty
	Blended
	Books
	Classical
	DigitalMusic
	DVD
	Electronics
	ForeignBooks
	GourmetFood
	Grocery
	HealthPersonalCare
	Hobbies
	HomeGarden
	HomeImprovement
	Industrial
	Jewelry
	KindleStore
	Kitchen
	Lighting
	Magazines
	Merchants
	Miscellaneous
	MP3Downloads
	Music
	MusicalInstruments
	MusicTracks
	OfficeProducts
	OutdoorLiving
	Outlet
	PCHardware
	PetSupplies
	Photo
	Shoes
	SilverMerchants
	Software
	SoftwareVideoGames
	SportingGoods
	Tools
	Toys
	UnboxVideo
	VHS
	Video
	VideoGames
	Watches
	Wireless
	WirelessAccessories
      ]


      # Search AWS for items. _search_index_ must be one of _SEARCH_INDICES_
      # and _parameters_ is an optional hash of parameters that further refine
      # the scope of the search.
      #
      # Example:
      #
      #  is = ItemSearch.new( 'Books', { 'Title' => 'ruby programming' } )
      #
      # In the above example, we search for books with <b>Ruby Programming</b>
      # in the title.
      #
      def initialize(search_index, parameters)
	unless SEARCH_INDICES.include? search_index.to_s
	  raise "Invalid search index: #{search_index}"
	end

	super( { 'SearchIndex' => search_index }.merge( parameters ) )
      end

    end


    # This class of look-up deals with searching for *specific* items by some
    # uniquely identifying attribute, such as the ASIN (*A*mazon *S*tandard
    # *I*tem *N*umber).
    #
    class ItemLookup < Operation

      # Look up a specific item in the AWS catalogue. _id_type_ is the type of
      # identifier and  _parameters_ is a hash that identifies the item to be
      # located and narrows the scope of the search.
      #
      # Example:
      #
      #  il = ItemLookup.new( 'ASIN', { 'ItemId' => 'B000AE4QEC'
      #					'MerchantId' => 'Amazon' } )
      #
      # In the above example, we search for an item, based on its ASIN. The
      # use of _MerchantId_ restricts the offers returned to those for sale
      # by Amazon (as opposed to third-party sellers).
      #
      def initialize(id_type, parameters)
	super( { 'IdType' => id_type }.merge( parameters ) )
      end

    end


    # Search for items for sale by a particular seller.
    #
    class SellerListingSearch < Operation

      # Search for items for sale by a particular seller. _seller_id_ is the
      # Amazon seller ID and _parameters_ is an optional hash of parameters
      # that further refine the scope of the search.
      #
      # Example:
      #
      #  sls = SellerListingSearch.new( 'A33J388YD2MWJZ',
      #					{ 'Keywords' => 'Killing Joke' } )
      #
      # In the above example, we search seller <b>A33J388YD2MWJ</b>'s listings
      # for items with the keywords <b>Killing Joke</b>.
      #
      def initialize(seller_id, parameters)
	super( { 'SellerId' => seller_id }.merge( parameters ) )
      end

    end


    # Return specified items in a seller's store.
    #
    class SellerListingLookup < ItemLookup

      # Look up a specific item for sale by a specific seller. _id_type_ is
      # the type of identifier and _parameters_ is a hash that identifies the
      # item to be located and narrows the scope of the search.
      #
      # Example:
      #
      #  sll = SellerListingLookup.new( 'AP8U6Y3PYQ9VO', 'ASIN',
      #					{ 'Id' => 'B0009RRRC8' } )
      #
      # In the above example, we search seller <b>AP8U6Y3PYQ9VO</b>'s listings
      # to find items for sale with the ASIN <b>B0009RRRC8</b>.
      #
      def initialize(seller_id, id_type, parameters)
	super( id_type, { 'SellerId' => seller_id }.merge( parameters ) )
      end

    end


    # Return information about a specific seller.
    #
    class SellerLookup < Operation

      # Search for the details of a specific seller. _seller_id_ is the Amazon
      # ID of the seller in question and _parameters_ is an optional hash of
      # parameters that further refine the scope of the search.
      #
      # Example:
      #
      #  sl = SellerLookup.new( 'A3QFR0K2KCB7EG' )
      #
      # In the above example, we look up the details of the seller with ID
      # <b>A3QFR0K2KCB7EG</b>.
      #
      def initialize(seller_id, parameters={})
	super( { 'SellerId' => seller_id }.merge( parameters ) )
      end

    end


    # Obtain the information an Amazon customer has made public about
    # themselves.
    #
    class CustomerContentLookup < Operation

      # Search for public customer data. _customer_id_ is the unique ID
      # identifying the customer on Amazon and _parameters_ is an optional
      # hash of parameters that further refine the scope of the search.
      #
      # Example:
      #
      #  ccl = CustomerContentLookup.new( 'AJDWXANG1SYZP' )
      #
      # In the above example, we look up public data about the customer with
      # the ID <b>AJDWXANG1SYZP</b>.
      #
      def initialize(customer_id, parameters={})
	super( { 'CustomerId' => customer_id }.merge( parameters ) )
      end

    end


    # Retrieve basic Amazon customer data.
    #
    class CustomerContentSearch < Operation

      # Retrieve customer information, using an e-mail address or name.
      #
      # If _customer_id_ contains an '@' sign, it is assumed to be an e-mail
      # address. Otherwise, it is assumed to be the customer's name.
      #
      # Example:
      #
      #  ccs = CustomerContentSearch.new( 'ian@caliban.org' )
      #
      # In the above example, we look up customer information about
      # <b>ian@caliban.org</b>. The *CustomerInfo* response group will return,
      # amongst other things, a _customer_id_ property, which can then be
      # plugged into CustomerContentLookup to retrieve more detailed customer
      # information.
      #
      def initialize(customer_id)
	id = customer_id =~ /@/ ? 'Email' : 'Name'
	super( { id => customer_id } )
      end

    end


    # Find wishlists, registry lists, etc. created by users and placed on
    # Amazon. These are items that customers would like to receive as
    # presnets.
    #
    class ListSearch < Operation

      # Search for Amazon lists. _list_type_ is the type of list to search for
      # and _parameters_ is an optional hash of parameters that narrow the
      # scope of the search.
      #
      # Example:
      #
      #  ls = ListSearch.new( 'WishList', { 'Name' => 'Peter Duff' }
      #
      # In the above example, we retrieve the wishlist for the Amazon user,
      # <b>Peter Duff</b>.
      #
      def initialize(list_type, parameters)
	super( { 'ListType' => list_type }.merge( parameters ) )
      end

    end


    # Find the details of specific wishlists, registries, etc.
    #
    class ListLookup < Operation

      # Look up and return details about a specific list. _list_id_ is the
      # Amazon list ID, _list_type_ is the type of list and _parameters_ is an
      # optional hash of parameters that narrow the scope of the search.
      #
      # Example:
      #
      #  ll = ListLookup.new( '3P722DU4KUPCP', 'Listmania' )
      #
      # In the above example, a *Listmania* list with the ID
      # <b>3P722DU4KUPCP</b> is retrieved from AWS.
      #
      def initialize(list_id, list_type, parameters={})
	super( { 'ListId'   => list_id,
	         'ListType' => list_type
	       }.merge( parameters ) )
      end

    end


    # Amazon use browse nodes as a means of organising the millions of items
    # in their inventory. An example might be *Carving Knives*. Looking up a
    # browse node enables you to determine that group's ancestors and
    # descendants.
    #
    class BrowseNodeLookup < Operation

      # Look up and return the details of an Amazon browse node. _node_ is the
      # browse node to look up and _parameters_ is an optional hash of
      # parameters that further refine the scope of the search. _parameters_
      # is currently unused.
      #
      # Example:
      #
      #  bnl = BrowseNodeLookup.new( '11232', {} )
      #
      # In the above example, we look up the browse node with the ID
      # <b>11232</b>. This is the <b>Social Sciences</b> browse node.
      #
      def initialize(node, parameters={})
	super( { 'BrowseNodeId' => node }.merge( parameters ) )
      end

    end


    # Similarity look-up is for items similar to others.
    #
    class SimilarityLookup < Operation

      # Look up items similar to _asin_, which can be a single item or an
      # array. _parameters_ is an optional hash of parameters that further
      # refine the scope of the search.
      #
      # Example:
      #
      #  sl = SimilarityLookup.new( 'B000051WBE' )
      #
      # In the above example, we search for items similar to the one with ASIN
      # <b>B000051WBE</b>.
      #
      def initialize(asin, parameters={})
	super( { 'ItemId' => asin.to_a.join( ',' ) }.merge( parameters ) )
      end

    end


    # Search for entities based on user-defined tags. A tag is a descriptive
    # word that a customer uses to label entities on Amazon's Web site.
    # Entities can be items for sale, Listmania lists, guides, etc.
    #
    class TagLookup < Operation

      # Look up entities based on user-defined tags. _tag_name_ is the tag to
      # search on and _parameters_ is an optional hash of parameters that
      # further refine the scope of the search.
      #
      # Example:
      #
      #  tl = TagLookup.new( 'Awful' )
      #
      # In the example above, we search for entities tagged by users with the
      # word *Awful*.
      #
      def initialize(tag_name, parameters={})
	super( { 'TagName' => tag_name }.merge( parameters ) )
      end

    end


    # Search for information on previously completed purchases.
    #
    class TransactionLookup < Operation

      # Return information on an already completed purchase. _transaction_id_
      # is actually the order number that is created when you place an order
      # on Amazon.
      #
      # Example:
      #
      #  tl = TransactionLookup.new( '103-5663398-5028241' )
      #
      # In the above example, we retrieve the details of order number
      # <b>103-5663398-5028241</b>.
      #
      def initialize(transaction_id)
	super( { 'TransactionId' => transaction_id } )
      end

    end


    # Look up individual vehicle parts.
    #
    class VehiclePartLookup < Operation

      # Look up a particular vehicle part. _item_id_ is the ASIN of the part
      # in question and _parameters_ is an optional hash of parameters that
      # further refine the scope of the search.
      #
      # Although the _item_id_ alone is enough to locate the part, providing
      # _parameters_ can be useful in determining whether the part looked up
      # is a fit for a particular vehicle type, as with the *VehiclePartFit*
      # response group.
      # 
      # Example:
      #
      #  vpl = VehiclePartLookup.new( 'B000C1ZLI8',
      #				      { 'Year' => 2008,
      #				        'MakeId' => 73,
      #				        'ModelId' => 6039,
      #				        'TrimId' => 20 } )
      #
      #	Here, we search for a <b>2008</b> model *Audi* <b>R8</b> with *Base*
      #	trim. The required Ids can be found using VehiclePartSearch.
      #
      def initialize(item_id, parameters={})
	super( { 'ItemId' => item_id }.merge( parameters ) )
      end

    end


    # Search for parts for a given vehicle.
    #
    class VehiclePartSearch < Operation

      # Find parts for a given _year_, _make_id_ and _model_id_ of vehicle.
      # _parameters_ is an optional hash of parameters that further refine the
      # scope of the search.
      #
      # Example:
      #
      #  vps = VehiclePartSearch.new( 2008, 73, 6039,
      #				      { 'TrimId' => 20,
      #				        'EngineId' => 8914 } )
      #
      # In this example, we look for parts that will fit a <b>2008</b> model
      # *Audi* <b>R8</b> with *Base* trim and a <b>4.2L V8 Gas DOHC
      # Distributorless Naturally Aspirated Bosch Motronic Electronic FI
      # MFI</b> engine.
      #
      # Note that pagination of VehiclePartSearch results is not currently
      # supported.
      #
      # Use VehicleSearch to learn the MakeId and ModelId of the vehicle in
      # which you are interested.
      #
      def initialize(year, make_id, model_id, parameters={})
	super( { 'Year'	   => year,
		 'MakeId'  => make_id,
		 'ModelId' => model_id }.merge( parameters ) )
      end

    end


    # Search for vehicles.
    #
    class VehicleSearch < Operation

      # Search for vehicles, based on one or more of the following
      # _parameters_: Year, MakeId, ModelId and TrimId.
      #
      # This method is best used iteratively. For example, first search on
      # year with a response group of *VehicleMakes* to return all makes for
      # that year.
      #
      # Next, search on year and make with a response group of *VehicleModels*
      # to find all models for that year and make.
      #
      # Then, search on year, make and model with a response group of
      # *VehicleTrims* to find all trim packages for that year, make and model.
      #
      # Finally, if required, search on year, make, model and trim package
      # with a response group of *VehicleOptions* to find all vehicle options
      # for that year, make, model and trim package.
      #
      # Example:
      #
      #  vs = VehicleSearch.new( { 'Year' => 2008,
      #				   'MakeId' => 20,
      #				   'ModelId' => 6039,
      #				   'TrimId' => 20 } )
      #
      # In this example, we search for <b>2008 Audi R8</b> vehicles with a
      # *Base* trim package. Used with the *VehicleOptions* response group,
      # a list of vehicle options would be returned.
      #
      def initialize(parameters={})
	super
      end

    end

    # Response groups determine which data pertaining to the item(s) being
    # sought is returned. They strongly influence the amount of data returned,
    # so you should always use the smallest response group(s) containing the
    # data of interest to you, to avoid masses of unnecessary data being
    # returned.
    #
    class ResponseGroup

      # The default type of response group to use with each type of operation.
      #
      DEFAULT = { 'BrowseNodeLookup'	  => [ :BrowseNodeInfo, :TopSellers ],
		  'CustomerContentLookup' => [ :CustomerInfo, :CustomerLists ],
		  'CustomerContentSearch' => :CustomerInfo,
		  'Help'		  => :Help,
		  'ItemLookup'		  => :Large,
		  'ItemSearch'		  => :Large,
		  'ListLookup'		  => [ :ListInfo, :Small ],
		  'ListSearch'		  => :ListInfo,
		  'SellerListingLookup'	  => :SellerListing,
		  'SellerListingSearch'	  => :SellerListing,
		  'SellerLookup'	  => :Seller,
		  'SimilarityLookup'	  => :Large,
		  'TagLookup'		  => [ :Tags, :TagsSummary ],
		  'TransactionLookup'	  => :TransactionDetails,
		  'VehiclePartLookup'	  => :VehiclePartFit,
		  'VehiclePartSearch'	  => :VehicleParts,
		  'VehicleSearch'	  => :VehicleMakes
      }

      # Define a set of one or more response groups to be applied to items
      # retrieved by an AWS operation.
      #
      # Example:
      #
      #  rg = ResponseGroup.new( 'Medium', 'Offers', 'Reviews' )
      #
      def initialize(*rg)
	@list = rg.join( ',' )
      end


      # We need a form we can interpolate into query strings.
      #
      def to_s	# :nodoc:
	@list
      end

    end


    # All dynamically generated exceptions occur within this namespace.
    #
    module Error

      # The base exception class for errors that result from AWS operations.
      # Classes for these are dynamically generated as subclasses of this one.
      #
      class AWSError < AmazonError; end

      def Error.exception(xml)
	err_class = xml.elements['Code'].text.sub( /^AWS.*\./, '' )
	err_msg = xml.elements['Message'].text

	# Dynamically define a new exception class for this class of error,
	# unless it already exists.
	#
	# Note that Ruby 1.9's Module.const_defined? needs a second parameter
	# of *false*, or it will also search AWSError's ancestors.
	#
	cd_params = [ err_class ]
	cd_params << false if RUBY_VERSION >= '1.9.0'

	unless Amazon::AWS::Error.const_defined?( *cd_params )
	  Amazon::AWS::Error.const_set( err_class, Class.new( AWSError ) )
	end

	# Generate and return a new exception from the relevant class.
	#
	Amazon::AWS::Error.const_get( err_class ).new( err_msg )
      end

    end


    # Create a shorthand module method for each of the AWS operations. These
    # can be used to create less verbose code at the expense of flexibility.
    #
    # For example, we might normally write the following code:
    #
    #  is = ItemSearch.new( 'Books', { 'Title' => 'Ruby' } )
    #  rg = ResponseGroup.new( 'Large' )
    #  req = Request.new
    #  response = req.search( is, rg )
    #
    # but we could instead use ItemSearch's associated module method as
    # follows:
    #
    #  response = Amazon::AWS.item_search( 'Books', { 'Title' => 'Ruby' } )
    #
    # Note that these equivalent module methods all attempt to use the *Large*
    # response group, which may or may not work. If an
    # Amazon::AWS::Error::InvalidResponseGroup is raised, we will scan the
    # text of the error message returned by AWS to try to glean a valid
    # response group and then retry the operation using that instead.


    # Obtain a list of all subclasses of the Operation class.
    #
    classes =
      ObjectSpace.enum_for( :each_object, class << Operation; self; end ).to_a

    classes.each do |cl|
      # Convert class name to Ruby case, e.g. ItemSearch => item_search.
      #
      class_name = cl.to_s.sub( /^.+::/, '' )
      uncamelised_name = Amazon.uncamelise( class_name )

      # Define the module method counterpart of each operation.
      #
      module_eval %Q(
	def AWS.#{uncamelised_name}(*params)
	  # Instantiate an object of the desired operational class.
	  #
	  op = #{cl.to_s}.new( *params )

	  # Attempt a search for the given operation using its default
	  # response group types.
	  #
	  results = Search::Request.new.search( op )
	  yield results if block_given?
	  return results

	end
      )
    end

  end

end
