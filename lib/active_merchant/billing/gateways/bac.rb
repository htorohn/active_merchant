module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BacGateway < Gateway
      self.test_url = 'https://credomatic.compassmerchantsolutions.com/api/transact.php'
      self.live_url = 'https://credomatic.compassmerchantsolutions.com/api/transact.php'

      self.supported_countries = ['HN']
      self.default_currency = 'HNL'
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      self.homepage_url = 'http://www.example.net/'
      self.display_name = 'BAC Gateway'

      RESPONSE_CODE = {
        '100' => 'Transaction was approved',
      }
      
      CVV_RESPONSE_CODE = {
        'M' => 'CVV2/CVC2 Match',
        'N' => 'CVV2/CVC2 No Match',
        'P' => 'Not Processed',
        'S' => 'Merchant has indicated that CVV2/CVC2 is not present on card',
        'U' => 'Issuer is not certified and/or has not provided Visa encryption keys'
      }
      
      AVS_RESPONSE_CODE = {
        'X' => 'Exact match, 9-character numeric ZIP',
        'Y' => 'Exact match, 5-character numeric ZIP',
        'D' => '',
        'M' => '',
        'A' => 'Address match only',
        'B' => '',
        'W' => '9-character numeric ZIP match only',
        'Z' => '5-character Zip match only',
        'P' => '',
        'L' => '',
        'N' => 'No address or ZIP match',
        'C' => '',
        'U' => 'Address unavailable',
        'G' => 'Non-U.S. Issuer does not participate',
        'I' => '',
        'R' => 'Issuer system unavailable',
        'E' => 'Not a mail/phone order',
        'S' => 'Service not supported',
        '0' => 'AVS Not Available',
        'O' => ''
      }

      def initialize(options={})
        requires!(options, :keyid, :hashkey)
        super
      end

      def purchase(money, payment, options={})
        post = {}
        add_key_id(post)
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_hash_time(post, money, options)
        add_address(post, payment, options)
        add_customer_data(post, options)
        #print("POST:\n")
        #print(post)
        commit('sale', post)
      end

      def authorize(money, payment, options={})
        post = {}
        add_key_id(post)
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_hash_time(post, money, options)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('auth', post)
      end

      def capture(money, authorization, options={})
        commit('capture', post)
      end

      def refund(money, authorization, options={})
        post = {}
        add_key_id(post)
        add_hash_time(post, money, options)
        add_transaction_id(post, authorization)
        add_invoice(post, money, options)

        commit('refund', post)
      end

      def credit(money, authorization, options={})
        post = {}
        add_key_id(post)
        add_hash_time(post, money, options)
        add_transaction_id(post, options)
        add_invoice(post, money, options)

        commit('refund', post)
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private
      
      def add_key_id(post)
        #print("Key: ")
        #print(@options[:key])
        post[:key_id] = @options[:keyid]
      end

      #Agregamos la informacion del cliente
      def add_customer_data(post, options)
        post[:ipaddress] = options[:ip]
        post[:email] = options[:email]
      end

      def add_transaction_id(post, authorization)
        post[:transactionid] = authorization
      end

      def add_address(post, creditcard, options)
      end

      #Agrega el monto y la modena a cobrar
      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:orderid] = options[:order_id]
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_amount(post, money)
        post[:amount] = amount(money)
      end

      #Agregamos el hash y el timestamp
      def add_hash_time(post, money, options)
        time = Time.now.to_i
        post[:time] = time
        
        parameters = Array.[](
          options[:order_id],
          amount(money),
          time,
          @options[:hashkey]
        )
  
        post[:hash] = Digest::MD5.hexdigest parameters.join("|")
        
      end

      #Agrega la informacion de la tarjeta de credito
      def add_payment(post, payment)
        post[:ccnumber] = payment.number

        post[:ccexp] = "#{payment.month}/#{payment.year}" || payment.ccExp
        post[:cvv] = payment.verification_value
      end

      def parse(body)
        #print("\nRESPONSE:")
        
        return {} if body.blank?
        #CGI::parse(body)
        #print(body)
        #print("\n")
        
        
        
        #print(URI::decode_www_form(body).to_h)
        URI::decode_www_form(body).to_h
      end

      def commit(action, parameters)
        url = (test? ? test_url : live_url)
        
        #print(url)
        #print(parameters)
        response = parse(ssl_post(url, post_data(action, parameters)))
        #print("RESPONSE:\n")
        #print(response)
        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(response["avsresponse"].blank? ? nil : response["avsresponse"].to_s),
          cvv_result: CVVResult.new(response["cvvresponse"].blank? ? nil : response["cvvresponse"].to_s),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        response['response'] == "1" ? response['response'] : nil
      end

      def message_from(response)
        response['responsetext']
      end

      def authorization_from(response)
        response['authcode']
      end

      def post_data(action, parameters = {}) 
        parameters[:type] = action
        return convert_to_url_form_encoded(parameters)
      end
      
      
      def convert_to_url_form_encoded(parameters, separator = "&")
        parameters.map do |key, value|
          next if value != false && value.blank?
          "#{key}=#{value}"
        end.compact.join(separator)
      end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
          response['response_code']
        end
      end
    end
  end
end
